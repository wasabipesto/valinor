# The Notes of Ereinion
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

# Hardware
My general-purpose server lives in DigitalOcean:
- DigitalOcean droplet, created 2/10/2022
- I intend to upgrade as I migrate things in (I'm looking at you, Synapse)
- 2 GB Memory / 50 GB Disk / NYC3 - Ubuntu 20.04 (LTS) x64

My compute/fileserver is on my home network:
- 2x Xeon 2678 v3, 64GB Memory
- 6x 12TB WD Elements shucked, in RAID5

Note: this repo is only for the general-purpose server. I'll get to the compute server eventually.

# First-time setup
SSH in for the first time! DO images are always super old, so we're going to update everything first.

	apt update
	apt upgrade

Now we set up a new user so we don't keep using the root account. Obviously change the username if you're one of the many people not named Justin. We're also going to move the ssh keys from the root account over to the new one.

	adduser justin
	mkdir /home/justin/.ssh
	mv .ssh/authorized_keys /home/justin/.ssh/authorized_keys
	chown -R justin:justin /home/justin/.ssh
	chown justin:justin /opt
	usermod -aG sudo justin

Now update our ssh config: Change sshd port from 22 to some other port, for security. Disable root login and password authentication.

	nano /etc/ssh/sshd_config
	service ssh restart
	logout

Log back in, but this time with feeling.

Disable the annoying MOTD (my preference):

	touch ~/.hushlogin

The raison d'etre! Note: Check your distro before adding the listed repository.

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

Connect the machine to the tailnet

	curl -fsSL https://tailscale.com/install.sh | sh
	sudo tailscale up

Just for me: set up git so I can push changes to this repository.

	ssh-keygen # then upload to github
	git config --global user.name "wasabipesto"
	git config --global user.email "21313833+wasabipesto@users.noreply.github.com"
	ssh -T git@github.com # test the config
	sudo apt install git-secret
	# grab gpg keys from backup
	gpg --import gpg-privkey.gpg

Pull this repository!

	git pull git@github.com:wasabipesto/ereinion.git
	cd erinion

And finish setting things up (again, just for me).

	git secret reveal
	chmod +x links.sh
	./links.sh
