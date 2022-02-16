# Project Valinor
My attempt to dockerise... everything.

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

	NEWUSER=[the user you just made]
	sudo apt install apt-transport-https ca-certificates curl software-properties-common haveged
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
	sudo apt update
	apt-cache policy docker-ce
	sudo apt install docker-ce
	sudo usermod -aG docker justin
	logout

Log back in to apply the user account changes (the ability to control docker via non-sudo). Then install docker-compose and test it out:

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
### Tailscale
I use tailscale to mesh all of my devices together. This makes routing between them super easy and much more secure than punching holes in firewalls and bypassing proxies. To connect this new machine to the tailnet:

	curl -fsSL https://tailscale.com/install.sh | sh
	sudo tailscale up

### Weavenet
### Traefik
### Authelia
### Nginx
### Fail2Ban/Crowdsec (TBD)

## Monitoring & Updates
### Watchtower
### Node-Exporter
### cAdvisor
### Prometheus
### Grafana
### AlertManager

## Communication
### Protonmail
Note: You will need to start the bridge first in inteactive mode.

	docker run --rm -it -v $OPDIR/protonmail:/root shenxn/protonmail-bridge init
	login

You can then use `info` to see the SMTP username/password.

### Apprise/Gotify
### Matrix/Synapse

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
