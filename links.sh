# Set up links from this repository to the correct places so containers can see their config files
#  Note: make sure you have a .env file with relevant variables and write access to $OPDIR.

if [ -f .env ]; then
    . .env
fi

ln -s $(pwd)/traefik $OPDIR/traefik

# Note: this will overwrite your .bash_aliases file!
ln $(pwd)/.bash_aliases ~/.bash_aliases
