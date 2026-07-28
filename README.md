# SICK User Workspace

## Introduction

[TOC]

The purpose of this repository is to store the SICK User Workspace for securing the TDC-Next environment, as the solution isolates the user's work environment in a specialized Docker cntainer. This repository stores the user environment in the form of a Dockerfile.

The next sections describe the Dockerfile environment.

## Docker Environment

The user workspace is built using the `arm64v8/ubutnu:24.04`.

To extend its functionality, the workspace includes a script for installing development tools, including:
  - base tools (`curl`, `git`, `openssh-client`, `vim`, etc.)
  - docker tools (`Docker` and `docker-cli`)
  - go (`go v1.24.4`)
  - grpcurl
  - network and monitoring tools (`btop`, `can-utils`, `iproute2`)

### Workspace Management

The workspace ships with a single `workspace` command that bundles every workspace control operation. Run it as `workspace <command>`; running `workspace` with no arguments shows the current workspace. The available commands are:

| Command | Description |
| --- | --- |
| `workspace current` | Show the workspace you are currently in |
| `workspace list` | List all available workspace containers |
| `workspace get-default` | Show which workspace is currently set as default |
| `workspace set-default [id]` | Set the default workspace (skips the menu on next login) |
| `workspace unset-default` | Clear the default — the selection menu reappears on login |
| `workspace switch` | Return to workspace selection (exits the current session) |
| `workspace help` | Show the command help |

The default selection is persisted in `/workspace/default-user-workspace`, and the list of detected containers is read from `/workspace/available-workspaces`. On an interactive SSH login, `workspace help` is shown automatically via `welcome.sh`.

The image is integrated with a `docker-compose.yml` file defined in the `TDC Firmware` project. The container is set up to work as Docker-outside-Docker, sharing the set up Docker Engine with the host's Engine.

See the `docker-compose.yml` file below:

```yaml
version: "3.9"

services:
  sick-user-workspace:
    image: ${WORKSPACE_IMAGE_NAME}
    container_name: sick-user-workspace
    cap_add:
      - NET_ADMIN
      - SYS_RAWIO
    logging:
        driver: "journald"
    volumes:
      - sick-user-workspace-data:/home/operator
      - /datafs/operator:/datafs/operator
      - /etc/os-release:/opt/sick/os-release:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/run/hal/:/var/run/hal/
      - /var/run/cc/:/var/run/cc/
      - /media/:/media/:shared
      - /run/log/journal/:/run/log/journal/:ro
    devices:
      - "/dev/serial/by-id/tdcx-serial:/dev/ttyUSB0"
    tmpfs:
      - /tmp
      - /run
    network_mode: host
    restart: always
    labels:
      com.sick.docker.builtin.sick-user-workspace: "true"
volumes:
  sick-user-workspace-data: {}
```

