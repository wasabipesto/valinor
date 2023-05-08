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
4. Media ingesting/requesting. Some services monitor certain channels and automatically add media that users request. This is less important than serving existing media.
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
	logout

Log back in, but this time with feeling.

Disable the annoying MOTD:

	touch ~/.hushlogin

Or make them fortunes instead:

	sudo apt install fortune
	sudo chmod -x /etc/update-motd.d/*
	echo fortune | sudo tee -a /etc/update-motd.d/20-fortune
	sudo chmod +x /etc/update-motd.d/20-fortune

The raison d'etre! Note: Check docker's official [installation instructions](https://docs.docker.com/engine/install/) as these may be out of date.

	sudo apt install apt-transport-https ca-certificates curl software-properties-common haveged
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
	sudo apt update
	apt-cache policy docker-ce
	sudo apt install docker-ce
	sudo usermod -aG docker [your user]
	logout

Install [docker compose v2](https://docs.docker.com/compose/cli-command/). Note that this version has only recently been introduced to [general availability](https://www.docker.com/blog/announcing-compose-v2-general-availability/) and v1 has not yet reached [end-of-life](https://github.com/docker/roadmap/issues/257) but I'm jumping on the v2 bandwagon because running a core feature of docker *inside a docker container* is ridiculous. 

	DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
	mkdir -p $DOCKER_CONFIG/cli-plugins
	curl -SL https://github.com/docker/compose/releases/download/v2.2.3/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
	chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

Then pull this repository!

	git pull git@github.com:wasabipesto/valinor.git
	cd valinor

# Documentation

You can find more detailed documentation [here](https://wasabipesto.com/notion).
