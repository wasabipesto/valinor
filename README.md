# Project Valinor
Like the elves unto Valinor, my services will embark upon ships (containers) and travel upon the straight road (VPN) to the Undying Lands (cloud). Also there will be some hobbits and a single dwarf for no particular reason.

This is my documentation for the project to migrate a bunch of services from bare metal/systemd to docker. I've experimented with docker a bit in the past and liked how easy it was to spin up new services and isolate runtime data from persistent volumes for easy updating. I have an old document with all of my notes from my current setup but I figured version history would be nice for this time 'round. The should be very little user-facing change as part of this move, basically everything is for my own benefit. It's also horribly overcomplicated, but it's for fun so who cares.

# Mindset
## Project goals
1. Upgradable: I should be able to upgrade each service independently without affecting user data or other services.
2. Adaptable: I should be able to add or remove services without major hassle. The fewer steps to spin up a new service, the better.
3. Reproducible: I should be able to recreate the entire structure on a new machine. This includes restoring backups of user data.
4. Consistent: Each service should have similar configuration and troubleshooting steps.
5. Monitored: I should know quickly if something is wrong, and user-facing issues should be announced automatically.
6. Connected: I should be able to run resource-intensive services on a separate node from other general services. All services should still be able to communicate.
7. Authenticated: All external requests should be authenticated before being passed into the network. 2FA would be preferred, but should not get in the way of usability.

## Not goals
1. Redundant: I do not need concurrent redundancy/load balancing for any services. My time is cheap, my services are small, and my users are forgiving.
2. Self-Healing: Nothing beyond updating and simple re-creation of docker containers will be necessary. 

## Hierarchy
1. Media serving through Plex. This is the highest priority. I start getting angry texts if it's down for more than 20 minutes.
2. Server administration/monitoring/backups. I should know if other things die before I need them to be not-dead.
3. Media serving through all other channels. This includes anything where you get the content through my server and then do something with it later (books, etc).
4. Media ingesting/requesting. Some services monitor certain channels and automatically add media users request. This is less important than serving existing media.
5. Incidentals. Anything that's just for me, or only used by other people only when I'm there to troubleshoot when things go wrong.

# Hardware
My general-purpose is named Erenion and lives in DigitalOcean:
- DigitalOcean droplet, created 2/10/2022
- 8 GB Memory / 160 GB Disk / NYC3 - Ubuntu 20.04 (LTS) x64

My compute/fileserver is named Celebrimbor and lives on my home network:
- 2x Xeon 2678 v3, 64GB Memory
- 7x 12TB WD Elements shucked, in RAID5

# First-time setup
SSH in for the first time! If you do this with DO's basic setup, you'll be dropped in as root. We're going to make good use of it and update everything first.

	apt update
	apt upgrade

Now we set up a new user so we don't keep using the root account. We're also going to move the ssh keys from the root account over to the new one so we can still login.

	NEWUSER=[username to be added]
	adduser $NEWUSER
	mkdir /home/$NEWUSER/.ssh
	mv .ssh/authorized_keys /home/$NEWUSER/.ssh/authorized_keys
	chown -R $NEWUSER:$NEWUSER /home/$NEWUSER/.ssh
	chown $NEWUSER:$NEWUSER /opt
	usermod -aG sudo $NEWUSER

Now update our ssh config: Change sshd port from 22 to some other port, for security. Disable root login and password authentication.

	nano /etc/ssh/sshd_config
	service ssh restart
	logout

Log back in, but this time with feeling.

Disable the annoying MOTD (my preference):

	touch ~/.hushlogin

The raison d'etre! Note: Check docker's official [installation instructions](https://docs.docker.com/engine/install/) as these may be out of date.

	sudo apt install apt-transport-https ca-certificates curl software-properties-common haveged
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
	sudo apt update
	apt-cache policy docker-ce
	sudo apt install docker-ce
	sudo usermod -aG docker [your user]
	logout

Install [docker compose v2](https://docs.docker.com/compose/cli-command/). Note that this version is not yet in [general availability](https://github.com/docker/roadmap/issues/257) but I'm trying it anyways.

	DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
	mkdir -p $DOCKER_CONFIG/cli-plugins
	curl -SL https://github.com/docker/compose/releases/download/v2.2.3/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
	chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

Then pull this repository!

	git pull git@github.com:wasabipesto/valinor.git
	cd valinor

#### Just for me
I need to set up git and git-secret to decrypt files and track changes.

	ssh-keygen 
	# upload public key to github, add to all other servers
	git config --global user.name [github username]
	git config --global user.email [github noreply email]
	ssh -T git@github.com # test the config
	
	sudo apt install git-secret
	# grab gpg keys from backup
	gpg --import gpg-privkey.gpg
	git secret reveal


# Services - Ereinion
## Networking
### [Tailscale](https://tailscale.com/)
I use tailscale to mesh all of my devices together. This makes routing between them super easy and much more secure than punching holes in firewalls and bypassing proxies. I also use the tailscale DNS system to make connections between devices easy to remember. To connect this new machine to the tailnet:

	curl -fsSL https://tailscale.com/install.sh | sh
	sudo tailscale up


### [Overlay Network](https://docs.docker.com/network/network-tutorial-overlay/#use-an-overlay-network-for-standalone-containers)
In order to work with multiple hosts, I have to set up an overlay network. This is exactly what I need, which is great, except Docker has forgotten that there are numbers between 1 and 100. Everything about overlay networks is a pain unless you're running in swarm mode, which I am not. In order to use overlay networks we have to turn on swarm mode and then ignore it forever. Sounds fun. As long as we shove it all through tailscale I think we'll be fine. If you're not using tailscale, get ready to poke some holes.

Pick one node as your "swarm manager". All other nodes will be "workers". 

On the manager, create the swarm but advertise it on the tailnet: `docker swarm init --advertise-addr [this server's tailscale IP]`

On the workers, join the swarm through the tailnet: `docker swarm join --advertise-addr [this server's tailscale IP] --token [token from manager] [manager's tailscale ip:port]`

On the manager, create the overlay network: `docker network create -d overlay --attachable [network name]`

This next part is very stupid. Docker workers do not see the manager's overlay network by default. You might think the workers would ask the manager when prompted with an unknown network. They do not. The only way, to my knowledge, to force a worker to learn about a network is to forcibly connect a container to it. This does not work through docker-compose.

On the workers, force discovery of the network: `docker run -d --rm --name prime --network wasabi-overlay alpine sleep 60`

You now have 60 seconds to join the overlay network via docker-compose. Because, and this is where is gets stupid, the worker _immediately forgets all overlay networks_ once the container exits. Once you've started your services via docker-compose, at least one container must continue running for the network to persist. If all containers die or disconnect from the network, you have to prime it again. 

I believe promoting the worker to a manager (`docker node promote [worker]` on the manager) solves this, but I'm not entirely sure.


### External Firewall
For every device, I have a firewall that lives outside of this configuration. This is because docker likes to [punch holes](https://news.ycombinator.com/item?id=27670058) in anything it can touch and I don't need to put up with forwarding ports anymore thanks to tailscale.

On Ereinion, I let DigitalOcean block all external requests except on ports 80 and 443. Traffic on these ports must pass through Traefik anyways.

On Celebrimbor, my home router blocks all external requests except on plex's port, and a few other legacy systems I'm moving as part of this project. 


### [Traefik](https://doc.traefik.io/traefik/)
Traefik is the backbone of this network. It is an edge router that sits in front of any request that comes in to the network (excepting tailscale). The main features I use are:

**Automatic Routing:** You'll see several entries in my docker-compose file that have labels like the ones below. These make it very simple to configure a new service, since the routin configuration lives next to the other provisioning information. Optionally I can forward to a login page or load-balance over multiple instances.

| Label | Effect |
| --- | --- |
| traefik.enable=true | Enables monitoring this container. |
| traefik.http.routers.example.entrypoints=websecure | Sets up a router within Traefik to look at traffic entering the network on this entrypoint. |
| traefik.http.routers.example.rule=Host(`example.$DOMAIN`) | Looks at the incoming hostname and send traffic to this container if it matches. |
| traefik.http.routers.example.middlewares=authelia@file | Forwards the request over to Authelia for login before serving the page. |

You will need to set the docker connection in your static configuration:

<details><summary>traefik/traefik.yml</summary>

	providers:
	  file:
	    directory: /etc/traefik/
	  docker:
	    exposedByDefault: false
	    endpoint: "unix:///var/run/docker.sock"
	
</details>

**HTTPS via Cloudflare:** Traefik automatically grabs and updates certificates for all of my domains via a DNS challenge to Cloudflare. It also redirects all incoming HTTP (port 80) traffic to HTTPS with the proper settings. You can see the redirect configuration here:

<details><summary>traefik/traefik.yml</summary>

	entryPoints:
	  web:
	    address: :80
	    http:
	      redirections:
		entryPoint:
		  to: websecure
	  websecure:
	    address: :443
	    http:
	      tls:
		certResolver: letsencrypt

</details>

Note: If you use Cloudflare, be sure to set the SSL/TLS setting to FULL, otherwise you will get stuck in endless redirects.


### [Authelia](https://www.authelia.com/docs/)
From the configuration above, Traefik passes along all requests for non-public services to the Authelia provider. Authelia then prompts the user to log in (with 2FA in my setup) before redirecting them on to the requested service. If the user has an existing session, they are forwarded automatically. This means you only need a single set of credentials for all internal services, and only need to log in once. 

You will need to set up Authelia as a forwardAuth middleware in Traefik's dynamic configuration:

<details><summary>authelia/configuration.yml</summary>

	http:
	  middlewares:
	    authelia:
	      forwardAuth:
		address: http://authelia:9091/api/verify?rd=https://auth.example.com/
		# Note: change the above domain to the subdomain you are hosting Authelia on
	
</details>

And then set up Authelia's configuration to accept, authenticate, and redirect back to the requested service. It has a lot of options that I don't need, so I used the [local configuration example](https://github.com/authelia/authelia/tree/master/examples/compose/local) as a template for my own. The main change from the example was to set the default policy to `two_factor` (I choose which services get redirected in the docker-compose labels, so anything passed to Authelia needs auth by definition).

#### Grafana Integration
You can tell Grafana to use authelia's forwarded headers with this snippet: 

<details><summary>grafana/grafana.ini</summary>

	[auth.proxy]
	enabled = true
	header_name = Remote-User
	header_property = username
	auto_sign_up = true # or false
	sync_ttl = 60

</details>

### [Nginx](https://github.com/nginxinc/docker-nginx)
I don't use nginx for anything besides a few static pages, but it's always nice to have. Nginx catches all of the base domain traffic.


## Monitoring & Updates
### [Watchtower](https://containrrr.dev/watchtower/)
Watchtower pulls new images for all of my containers and updates/recreates them as necessary. While it might be a security risk to automatically pull updates from `:latest`, it's not like I would have been more vigilant updating them all manually with `docker-compose up` anyways (provided I remembered to do it at all). Plus now I get notifications.


### [Prometheus](https://prometheus.io/docs/introduction/overview/)/[Node-Exporter](https://prometheus.io/docs/guides/node-exporter/)/[cAdvisor](https://prometheus.io/docs/guides/cadvisor/)/[Grafana](https://grafana.com/docs/grafana/latest/installation/docker/)
The services in this stack:
- Prometheus pulls metrics from a bunch of different places and collates them for analysis. 
  - Note: The base prometheus image runs under a weird user and does not respect the docker-compose user settings. You have to set the data directory on the host to be writable/owned by user 65534 (or set chmod 777).
- Node-Exprter grabs metrics from the host servers and makes them available to Prometheus.
  - Note: If you have multiple instances of a service (like node-exporter), make sure you add the hostname property to each container so prometheus can tell them apart.
- cAdvisor grabs metrics from each container and makes them available to Prometheus.
- Grafana makes pretty graphs and alerts me if there are problems.
  - Note: I have pulled out a custom `grafana.ini` file and placed it at `/var/lib/grafana`. Grafana will not start unless you manually place a valid ini file there. If you want to use the defaults, remove the environment variable `GF_PATHS_CONFIG`.

After setting everything up, you need to tell Prometheus where to scrape from. This is part of my configuration:

<details><summary>prometheus/prometheus.yml</summary>

	global:
	scrape_interval: 15s

	scrape_configs:
	- job_name: 'prometheus'
		static_configs:
		- targets: ['localhost:9090']

	- job_name: 'node'
		static_configs:
		- targets: ['node-ereinion:9100']
		- targets: ['node-celebrimbor:9100']

	- job_name: 'cadvisor'
		static_configs:
		- targets: ['cadvisor-ereinion:8080']
		- targets: ['cadvisor-celebrimbor:8080']

	and so on

</details>


## Communication
### [Protonmail](https://github.com/shenxn/protonmail-bridge-docker)
I use Protonmail for my email, which means I can't simply forward SMTP requests to them in order to send mail from my server. They do have a bridge that works well enough in docker, so that's my "email server" now. Since it lives within the docker network, it's easy enough to configure various other services to just see the bridge as a valid email server. If I ever waned to read mail I would have to install something else, but I don't so I won't.

Note: For first-time setup, you will need to start the bridge in interactive mode and log in:

	docker run --rm -it -v $OPDIR/protonmail:/root shenxn/protonmail-bridge init
	login
	# authenticate
	info

This will authenticate the bridge with Protonmail and store the session in $OPDIR. You can then use `info` to see the bridge's SMTP username/password and use that to connect from other containers. Note that the bridge is lying to you, port 1025 is not exposed from the container (use port 25 instead, and you'll probably have to disable tls checking).


### [Matrix](https://matrix.org/)/[Synapse](https://github.com/matrix-org/synapse)
In order to run, synapse needs a configuration file located at /data/homeserver.yaml. You can have it generate one automatically with your domain by using: 

<details><summary>docker run</summary>

	docker run -it --rm \
		-v /opt/synapse:/data \
		-e SYNAPSE_SERVER_NAME=[your domain] \
		-e SYNAPSE_REPORT_STATS=yes \
		-e UID=1000 \
		-e GID=1000 \
		matrixdotorg/synapse:latest generate

</details>

Then pop over and edit it to your liking. This will also generate some other random necessary files in synapse's default structure. If you spin it up now, you should get a nice little "it works!" page. 

NOTE: The domain you use in that command should be your base domain (example.com NOT matrix.example.com). If you mess this up, just delete it and start over. Trust me.

Next I'm going to give synapse a postgres database because we outgrew our sqlite pants a few years ago. When you specify the postgres container in compose, just give it a username, password, and startup options. Note: when you first launch postgres, it will try to initialize the database. It [cannot](https://github.com/docker-library/postgres/pull/253) do this while running under some UIDs. What I do is run it once as the default user (UID 40), stop the container, chown the files back to 1000, then recreate the container running as 1000. Something something stateless architecture.

After that's done, synapse will log in with the hostname, username, and password you specify in the config:

<details><summary>synapse/homeserver.yaml</summary>

	database:
	  name: psycopg2
	  txn_limit: 10000
	  args:
		user: synapse
		password: [that password you set in your .env for postgres]
		database: synapse
		host: postgres-synapse
		port: 5432
		cp_min: 5
		cp_max: 10

</details>

If you use redis for worker management, you can do that here too. I won't, but you can. 

Synapse follows [these rules](https://spec.matrix.org/latest/server-server-api/#resolving-server-names) to find your server. 
- As a first step it assumes synapse is available at port 8448 and tries contacting it there. If you're comfortable allowing non-proxied traffic into your network, you can just open port 8448 on traefik and pipe all of that directly to synapse for it to deal with. 
- Unfortunately, I've gone to some hassle to make all of cloudflare's buttons orange so we're going to do it the hard way. The next step is to look for a .well-known file at the base domain (served over port 443) that lists where we can find synapse. 
- Interestingly, synapse is capable of generating this file for us. When we pass it [this configuration](https://matrix-org.github.io/synapse/latest/delegate.html) it will put the .well-known files from the internal webserver. We can copy those over to nginx to point new connections in the right direction.
- Now, since synapse is already capable of falling back to port 443 to check for a .well-known file (which is ironically served by synapse) why doesn't it just fall back to federation over port 443? We may never know. 

And then we run the [federation tester](https://federationtester.matrix.org) to make sure everything checks out. Note: You may need to set the MIME types of the `server` and `client` files to application/json in nginx.

I also like to enable metrics and some other goodies:

<details><summary>synapse/homeserver.yaml</summary>

	enable_metrics: true
	listeners:
		...
		- port: 9000
			type: metrics
			bind_addresses:
			- '0.0.0.0'

	url_preview_enabled: true
	url_preview_ip_range_blacklist:
	- '127.0.0.0/8'
	- '10.0.0.0/8'
	- '172.16.0.0/12'
	- '192.168.0.0/16'
	- '100.64.0.0/10'
	- '192.0.0.0/24'
	- '169.254.0.0/16'
	- '192.88.99.0/24'
	- '198.18.0.0/15'
	- '192.0.2.0/24'
	- '198.51.100.0/24'
	- '203.0.113.0/24'
	- '224.0.0.0/4'
	- '::1/128'
	- 'fe80::/10'
	- 'fc00::/7'
	- '2001:db8::/32'
	- 'ff00::/8'
	- 'fec0::/10'

</details>


### [Element](https://github.com/vector-im/element-webd)
Element is really simple to set up, you don't even really need to mount the config file if you're okay with the defaults. If you do, make sure you create an empty file first. Otherwise docker will create a folder there, which you probably don't want.

<details><summary>element/config.json (optional)</summary>

    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://synapse.wasabipesto.com",
            "server_name": "wasabipesto.com"
        }
    "brand": "Matrix via WasabiPea",
    "default_theme": "dark",
	...
    "showLabsSettings": true,
	...
	etc.

</details>


### [Heisenbridge](https://github.com/hifi/heisenbridge)
Heisenbridge is like ZNC but for matrix. When you first start heisenbridge it will need to generate a registration file:

<details><summary>docker run</summary>

	docker run --rm \
		-v [/opt]/synapse:/data \
		hif1/heisenbridge \
		-c /data/heisenbridge.yaml \
		-l 0.0.0.0 \
		--generate \
		-o @[admin user]:example.com

</details>

Then in your synapse homeserver.yaml you will need to add:

<details><summary>synapse/homeserver.yaml</summary>

	app_service_config_files:
	  - /data/heisenbridge/heisenbridge.yaml

</details>

Note that in all of the registration files for synapse, both containers must be able to communicate with each other. This means providing each with the other's container name (which is resolved via docker DNS) and exposed port.


### [mx-puppet-groupme](https://gitlab.com/robintown/mx-puppet-groupme)/[mx-puppet-discord](https://github.com/matrix-discord/mx-puppet-discord)
The mx-puppet bridges all work similarly. You pass them a config file, they generate a registration file, synapse reads the registration file, they negotiate from there. 

<details><summary>synapse/mx-puppet-[bridge]/config.yaml</summary>

	port: [default port]
	bindAddress: [resolvable container name]
	domain: [base url (example.com)]
	homeserverUrl: [matrix federation url (synapse.example.com)]

</details>

<details><summary>synapse/mx-puppet-whatever/config.yaml</summary>

	url: 'http://mx-puppet-[bridge]:[port]'

</details>

<details><summary>synapse/homeserver.yaml</summary>

	app_service_config_files:
	  - /data/mx-puppet-[bridge]/[bridge]-registration.yaml

</details>

## Backup
### [Syncthing](https://docs.syncthing.net/)
A nice replacement for dropbox, minus all of the annoying features. Still experimenting with usability. Right now the goal is to have buckets for notes, projects, and other random documents that sync to ereinion and all relevant devices. Then the files get backed up to b2 via restic or whatever.


### Other Backup
Still evaluating. Trying to have everything back up to b2 for easy restores. Looking into restic, will probably have to roll my own image/scripts.


## Games
### [WikiJS](https://docs.requarks.io/)
A good wiki platform that I like to integrate with discord for easy user management. Mainly a platform for D&D notes. It spits out markdown files every day and has the option to sync bidirectionally, which I may pair with syncthing + obsidian at some point.


### [Foundry](https://github.com/felddy/foundryvtt-docker)
This Foundry image downloads the newest app version every time it starts, which is an interesting choice. It mounts in all of the config, system, and world files from there and boots up into a session. I have multiple sessions hosted on seperate containers so I can have them running simultaneously.


## Media
### [Tautulli](https://github.com/Tautulli/Tautulli)
Monitor Plex and see what people actually watch. A lot of the features I used to use (watch history, notifications, auto-updates) have since been replaced by other services, but it's nice to keep around.


### [Overseerr](https://docs.overseerr.dev/)
A request system so simple and pretty my parents could use it. The absolute killer feature being that you log in with your Plex account, so you don't need to remember another password. Get notifications when your requests are added or your issues resolved.


### [Owncast](https://owncast.online/docs/)
A simple self-serve streaming site. Yet to use extensively. The RTMP port is exposed outside of docker, but the DO firewall blocks incoming connections on that port. In order to stream to the container you must be on the tailnet or set an exception in the firewall. Or add a rule to traefik, I guess.


## Other
### [Code-Server](https://github.com/coder/code-server)
I have code-server set up with its own local storage for settings and config, and then another mount to /opt for my entire working directory. This lets me edit yaml/config files through all of my services without doing a thing. As an added bonus I can ssh into the host (172.17.0.1 by default) and run docker commands in the same window! Pretty handy so far.


### [Jupyter](https://docs.jupyter.org/en/latest/)
Jupyter is quite nice for ingesting and visualizing lots of data. This container is a bit finnicky to get set up, I'd like to get it under control at some point.


### [Flame](https://github.com/pawelmalak/flame)
A pretty dashboard for all of my stuff. More importantly, it adds items from docker labels. I'm still hoping for header auth (or just no auth) but what's there works great.

To add a service to flame, add the following labels:
      - flame.type=application # this can be set to anything, flame just checks to see if the flag is present at all
      - flame.name=owncast # the name of the item in flame
      - flame.url=https://stream.$DOMAIN # the connectable address (probably the same as what you proxied)
      - flame.icon=twitch # mdi icon for the service

You cannot set descriptions with labels at this time, but it's [in development](https://github.com/pawelmalak/flame/pull/315). Same story with [multiple docker hosts](https://github.com/pawelmalak/flame/pull/321).


### [Guacamole](https://guacamole.apache.org/doc/gug/guacamole-docker.html)
A browser-based clientless remote access solution. I use it for VNC connections to my server and RDP connections to my desktop while away from home. It also supports SSH and other goodies. This docker image was pretty simple to configure in comparison to bare metal, and it even connects with authelia for header auth. 

First, generate the initialization script: `docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgres > ./initdb.sql`

Then, run postgres with the script mounted: `./initdb.sql:/docker-entrypoint-initdb.d/initdb.sql:ro`

If you like to run postgres as a different user, stop the container (`docker stop postgres-guacamole`) and chmod the data directory (`sudo chown -R 1000:1000 $OPDIR/postgres-guacamole`).

Optionally, edit the compose file to remove the script mount and change the user. Once everything's running. Log in with the default username/password `guacadmin`/`guacadmin` and change the password. 

If you're trying to connect to a windows machine using RDP, make sure you use the target user's username and password, and check `ingore server certificate`. 

In order to transparently add the `/guacamole` prefix, we use traefik's addprefix middleware: `traefik.http.middlewares.guac-prefix.addprefix.prefix=/guacamole`

There seems to be an issue with using newer keys to authenticate ssh. Not too worried about it since I have other ways of accessing ssh via web (cose-server) and mobile (juicessh).


# Services - Celebrimbor
As my file server and compute server, Celebrimbor handles anything directy related to media ingestion, storage, and serving to users. If other servers go down, these services hsould at least be able to continue core functions, even if they can't be served through the proxy.

### A note on networking
Since (to my knowledge) traefik cannot see the labels on another host's docker engine, it cann't route to these containers based on those labels. Instead, those routers and services are listed in traefik's dynamic configuration.

## Monitoring
### Watchtower/Node-Exporter/cAdvisor
See above. All stats get scraped by Prometheus over on ereinion.


## Media
### [r+utorrent](https://github.com/crazy-max/docker-rtorrent-rutorrent)
As far as I've found, r(u)torrent is the only solution for managing a large amount of torrents. Since I use sonarr/radarr's hardlink function, as long as I keep the media in one form or another I can keep seeding it. So I have rtorrent set up to download to a special `$DATADIR` which lives on celebrimbor's RAID array and sonarr/radarr pull from there. One thing to note: the path for this folder should be mapped the same in every container (ie /data/downloads). 

If this container ever becomes unmanageable, I'll probably spin it off somehow and just start a new one. Did I mention docker networking is uper easy?

If you choose to use sonarr/radarr, there are a few things to note here. First, to connect you must use the following settings:
- Host: rtorrent (conatiner name)
- Port: 8080 (r*u*torrent port)
- Path: RPC2

Then, make sure your labels are all unique between radarr/sonarr/etc. If any share labels (ie, `unfinished`) they will all take responsibility at the same time and try to sort it/throw errors when they cannot.


### [FileBrowser](https://github.com/filebrowser/filebrowser)
Filebrowser sits on the storage server and has a nice little webui so I can move/edit/upload/download anything on-the-go. More importantly, it has a "sharing" feature where I can click on any file and generate a link to it (with password and/or time limit) for easy and secure access.

Note: you cannot run `filebrowser config` or similar commands while filebrowser is [running in docker](https://github.com/filebrowser/filebrowser/issues/1036), even with `docker exec`. In order to do things like set up proxy auth, you must do the following:
1. Stop the running container with `docker stop filebrowser`
2. Add/Uncomment the line in the relevant docker-compose.yml that specifies `entrypoint: /bin/sh`
3. Run `docker compose run filebrowser` and wait for it to drop you into the shell
4. Run whatever command you want, like `./filebrowser config set --auth.method=proxy --auth.header=Remote-User`
5. Exit the conatiner and uncomment/remove the entrypoint line in your docker-compose.

There is probably an easier way, but that's how I got it working.

In order to allow others to reach your (explicity) shared files, you will need to add a second router to your traefik configuration. The routers should look something like:

<details><summary>traefik/traefik.yml</summary>

	routers:
		filebrowser:
			entrypoints:
				- "websecure"
			rule: "Host(`filebrowser.example.com`)"
			middlewares:
				- authelia
			service: filebrowser
		filebrowser-share:
			entrypoints:
				- "websecure"
			rule: "Host(`filebrowser.example.com`) && (PathPrefix(`/share`) || PathPrefix(`/api/public`))"
			service: filebrowser
	...
	services:
		filebrowser:
		loadBalancer:
			servers:
			- url: "http://filebrowser:80"
	
</details>


### [Prowlarr](https://wiki.servarr.com/prowlarr)
I used to use Jackett, but a [single](https://wiki.servarr.com/sonarr/troubleshooting#tracker-needs-rawsearch-caps) [issue](https://github.com/Jackett/Jackett/pull/11889) has pushed me to move to Prowlarr. If an indexer is doing its job, you won't be sure it's there at all.


### [Sonarr](https://wiki.servarr.com/sonarr)/[Radarr](https://wiki.servarr.com/radarr)
Sonarr and Radarr are the core of my media ingestion. The typical flow looks like:

1. I (or a user) request an item through Overseerr. The settings in Overseerr determine the standard quality profile, destination folder, etc.
2. That information is passed along to the relevant {son,rad}arr container. It autommatically sets up an RSS watch to look for new items matching that request and, depending on the settings, also begins a backfill search.
3. Those requests are passed to Prowlarr, which is connected to all of my trackers. It will cache, bundle, and interpet content-aware requests before passing them off to the relevant trackers.
4. If anything is found, it will be sent to rtorrent to download. Sonarr and radarr will poll rtorrent to find out when the download is complete and then hardlink the file into Plex's media directory.
5. Plex (hopefully) sees the file and parses it correctly, making it available to stream.

I didn't have to do anything fancy to set up these images. I may look into other *arrs in the future, their stack has been working pretty well for me.


### [Calibre](https://calibre-ebook.com/) & [Calibre-Web](https://github.com/janeczku/calibre-web)
LSIO bundles together calibre and calibre-web, which is auful nice of them. All I had to do was pull in my existing database and point it at the books.

Unfortunately there's an [issue](https://github.com/janeczku/calibre-web/issues/1466) in calibre-web right now that invalidates sessions coming through cloudflare. The solution is to pin the image at 0.6.12 and add a script to `custom-cont-init.d` that modifies the program at launch (not a fan). Also apparently amazon's requiring that you verify all emails sent to your kindle, which kinda sucks.


## Other
### [Home Assistant](https://www.home-assistant.io/docs/)
Home Assistant is great for running physical devices and sensors in the home. I also use it for simple automations and monitoring. Most of the fiddly configuration is held in yaml files that I can mount and back up however I please.

Note: when you launch this docker-compose Home Assistant will not accept proxied connections by default. You can enable this setting by adding the following to the configuration file. Be sure to change the trusted_proxies whitelist to something matching your traefik installation.

<details><summary>homeassistant/configuration.yml</summary>

	http:
		use_x_forwarded_for: true
		trusted_proxies:
			- 10.0.1.0/24

</details>

Another note: if Home Assistant is running with `network_mode: host`, you cannot connect to it with the standard docker DNS system where you just call it `homeassistant`. Instead, you must connect to `celebrimbor:8123` (or whatever your host's hostname is (assuming you're using tailscale's DNS)). This is relevant for both traefik to proxy traffic in and prometheus to scrape metrics out.


## Untouched
### [Plex](https://support.plex.tv/articles/200264746-quick-start-step-by-step-guides/)
Being the core of my software stack, I'm probably going to end up leaving this one out of docker. Will re-evaluate later.


# Next Steps
- Finish setting up jupyter, ideally with easy authentication
- Finish setting up restic, maybe with ofelia
- Install loki to monitor logs
- Install NUT and components to monitor server UPS
- Implement goodies from flame 2.2.2 once released
- Implement mx-puppet-discorda and calibre latest versions once fixed
- Implement authelia header auth wherever possible
- Look into Unigraph for brower-based notes & feeds
- Look into a proper LDAP server
