# Common commands for dealing with docker compose configurations.

config_file := join(justfile_directory(), shell("hostname") + "-compose.yml")

# List commands, default
default:
  just --list

# Update config from git
update:
    git pull

# List all conatiners
ps:
    docker ps

# Evaluate and show full configuration
get-config *args:
    docker compose -f {{config_file}} config {{args}}

# Start a container or all containers
up *args:
    docker compose -f {{config_file}} up -d {{args}}

# Start a container and immateiately start tailing logs
uplog container:
    just up {{container}}
    just logs -f {{container}}

# Stop a container
down container:
    docker compose -f {{config_file}} down {{container}}

# Stop all containers (!!!)
[confirm]
down-all:
    docker compose -f {{config_file}} down

# Restart a container
restart container:
    docker compose -f {{config_file}} restart {{container}}

# Build/rebuild a container
build container:
    docker compose -f {{config_file}} build {{container}}

# Get logs for a container or all containers
logs *args:
    docker compose -f {{config_file}} logs -f {{args}}

# Get shell in a running container
shell container:
    docker exec -it {{container}} bash || \
        docker exec -it {{container}} sh
