# Set up links from this repository to the correct places so containers can see their config files
#  Note: make sure you have a .env file with relevant variables and write access to $OPDIR.

if [ -f .env ]; then
    . .env
fi

mkdir $OPDIR/traefik
ln $(pwd)/traefik/traefik.yml $OPDIR/traefik/traefik.yml
ln $(pwd)/traefik/users $OPDIR/traefik/users
