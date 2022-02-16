# Project Valinor
Like the elves unto Valinor, my services will embark upon ships (containers) and travel upon the straight road (VPN) to the Undying Lands (cloud). Also there will be some hobbits and a single dwarf for no particular reason.

# Top-level goals
1. Upgradable: I should be able to upgrade each service independently without affecting user data or other services.
2. Adaptable: I should be able to add or remove services without major hassle. The fewer steps to spin up a new service, the better.
3. Reproducible: I should be able to recreate the entire structure on a new machine. This includes restoring backups of user data.
4. Consistent: Each service should have similar configuration and troubleshooting steps.
5. Monitored: I should know quickly if something is wrong, and user-facing issues should be announced automatically.
6. Connected: I should be able to run resource-intensive services on a separate node from other general services. All services should still be able to communicate.
7. Authenticated: All external requests should be authenticated before being passed into the network. 2FA would be preferred, but should not get in the way of usability.

## Not goals:
8. Redundant: I do not need concurrent redundancy/load balancing for any services. My time is cheap, my services are small, and my users are forgiving.
9. Self-Healing: Nothing beyond updating and simple re-creation of docker containers will be necessary. 

# Hardware
My general-purpose is named Erenion server lives in DigitalOcean:
- DigitalOcean droplet, created 2/10/2022
- I intend to upgrade as I migrate things in (I'm looking at you, Synapse)
- 2 GB Memory / 50 GB Disk / NYC3 - Ubuntu 20.04 (LTS) x64

My compute/fileserver is named Celebrimbor and lives on my home network:
- 2x Xeon 2678 v3, 64GB Memory
- 6x 12TB WD Elements shucked, in RAID5

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

Log back in to apply the user account changes (the ability to control docker via non-sudo). Then [install docker-compose](https://docs.docker.com/compose/install/) and test it out:

	sudo curl -L --fail https://github.com/linuxserver/docker-docker-compose/releases/download/1.27.4-ls17/docker-compose-amd64 -o /usr/local/bin/docker-compose
	sudo chmod +x /usr/local/bin/docker-compose
	docker-compose -v # pull the image and test

Pull this repository!

	git pull git@github.com:wasabipesto/valinor.git
	cd valinor

### Just for me
I need to set up git and git-secret to decrypt files and track changes.

	ssh-keygen 
	# upload public key to github
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

### [Weave Net](https://www.weave.works/docs/net/latest/overview/)
TODO

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

	providers:
	  file:
	    directory: /etc/traefik/
	  docker:
	    exposedByDefault: false
	    endpoint: "unix:///var/run/docker.sock"

**HTTPS via Cloudflare:** Traefik atomatically grabs and updates certificates for all of my domains via a DNS challenge to Cloudflare. It also redirects all incoming HTTP (port 80) traffic to HTTPS with the proper settings. You can see the redirect configuration here:

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

Note: If you use Cloudflare, be sure to set the SSL/TLS setting to FULL, otherwise you will get stuck in endless redirects.

### [Authelia](https://www.authelia.com/docs/)
From the configuration above, Traefik passes along all requests for non-public services to the Authelia provider. Authelia then prompts the user to log in (with 2FA in my setup) before redirecting them on to the requested service. If the user has an existing session, they are forwarded automatically. This means youo only need a single set of credentials for all internal services, and only need to log in once. 

You will need to set up Authelia as a forwardAuth middleware in Traefik's dynamic configuration:

	http:
	  middlewares:
	    authelia:
	      forwardAuth:
		address: http://authelia:9091/api/verify?rd=https://auth.example.com/
		# Note: change the above domain to the subdomain you are hosting Authelia on

And then set up Authelia's configuration to accept, authenticate, and redirect back to the requested service. It has a lot of options that I don't need, so I used the [local configuration example](https://github.com/authelia/authelia/tree/master/examples/compose/local) as a template for my own. The main change from the example was to set the default policy to `two_factor` (I choose which services get redirected in the docker-compose labels, so anything passed to Authelia needs auth by definition).

### Nginx
I don't use nginx for anything besides a few static pages, but it's always nice to have.

### Fail2Ban/Crowdsec
TODO: I don't think I need this, but we'll see.

## Monitoring & Updates
### Watchtower
### Node-Exporter
### cAdvisor
### Prometheus
### Grafana
### AlertManager

## Communication
### [Protonmail](https://github.com/shenxn/protonmail-bridge-docker)
I use Protonmail for my email, which means I can't simply forward SMTP requests to them in order to send mail from my server. They do have a bridge that works well enough in docker, so that's my "email server" now. Since it lives within the docker network, it's easy enough to configure various other services to just see the bridge as a valid email server. If I ever waned to read mail I would have to install something else, but I don't so I won't.

Note: For first-time setup, you will need to start the bridge in interactive mode and log in:

	docker run --rm -it -v $OPDIR/protonmail:/root shenxn/protonmail-bridge init
	login
	# authenticate
	info

This will authenticate the bridge with Protonmail and store the session in $OPDIR. You can then use `info` to see the bridge's SMTP username/password and use that to connect from other containers. Note that the bridge is lying to you, port 1025 is not exposed from the container (use port 25 instead, and you'll probably have to disable tls checking).

### Apprise/Gotify
TODO: To pass along urgent notifications.

### Matrix/Synapse
TODO: Utilize the matrix-ansible-docker-deploy script with traefik proxy.

## Backup
### Syncthing
### FileBrowser
### Duplicacy/Borg

## D&D
### WikiJs
### PostgreSQL
### Foundry

## Media
### Tautulli
### Overseerr
### Prowlarr

## Code
### Jupyter
### Code-Server

# Services - Celebrimbor
## Media
### Torrent Client TBD
### FileBrowser
### Sonarr
### Radarr
### Lidarr
### Calibre
### Calibre-Web
### Plex

## Monitoring
### Node-Exporter
### Exportarr
### Scrutiny

## Other
### HomeAssistant
