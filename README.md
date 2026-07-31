# RAW-Network Homelab

A collection of Docker Compose stacks and utilities for building and managing self-hosted services

This repository contains modular Docker Compose projects that can be deployed independently. Every stack is isolated in its own directory, making it easy to install, update, and maintain only the services you need

The repository also includes **stackctl**, a lightweight utility for managing multiple Docker Compose stacks from a single interactive menu

---

## Requirements

Before getting started, make sure the following software is installed

* Docker Engine
* Docker Compose v2
* Git

Verify the installation

```bash
docker --version
docker compose version
git --version
```

---

## Clone the Repository

Clone the repository to your server or local machine

```bash
git clone https://github.com/RAW-Network/homelab.git
```

Move into the project directory

```bash
cd homelab
```

---

## Repository Layout

Each application is stored in its own directory

```text
homelab/
├── docker/
│   └── container/
│       ├── app-1/
│       ├── app-2/
│       ├── app-3/
│       └── ...
│
├── stackctl.sh
└── README.md
```

Open the folder of the application you want to deploy

```bash
cd docker/container/<stack-name>
```

---

## Deploy a Stack

Start the selected stack

```bash
docker compose up -d
```

Check running containers

```bash
docker compose ps
```

View container logs

```bash
docker compose logs -f
```

Stop the stack

```bash
docker compose down
```

Update the stack

```bash
docker compose pull
docker compose up -d
```

---

## Managing Multiple Stacks

Managing many Compose projects manually can become repetitive. This repository includes **stackctl** to simplify common operations such as deploying, updating, and stopping multiple stacks at once.

Run directly without installation

```bash
curl -sSL https://raw.githubusercontent.com/RAW-Network/homelab/main/stackctl.sh | bash
```

Or run the script locally

```bash
chmod +x stackctl.sh
./stackctl.sh
```

Install globally

```bash
curl -sSL https://raw.githubusercontent.com/RAW-Network/homelab/main/stackctl.sh -o stackctl.sh

chmod +x stackctl.sh

sudo mv stackctl.sh /usr/local/bin/stackctl
```

Launch from anywhere

```bash
stackctl
```

---

## Directory Requirements for stackctl

`stackctl` automatically scans the current directory for Docker Compose projects

Each stack should be stored inside its own folder and contain a supported Compose file

```text
AppData/
├── immich/
│   └── docker-compose.yml
├── portainer/
│   └── docker-compose.yml
├── jellyfin/
│   └── docker-compose.yml
└── ...
```

Supported file names

* docker-compose.yml
* docker-compose.yaml
* compose.yml
* compose.yaml

---

## License

This project is licensed under the MIT License

See the [LICENSE](LICENSE) file for more information
