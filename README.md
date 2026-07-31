# Homelab

Docker Compose collection and stack management tool for self-hosted services.

---

## Getting Started

### Prerequisites

- Docker Engine
- Docker Compose v2+

### Deploy a Single Service

```bash
git clone https://github.com/RAW-Network/homelab.git
cd homelab/docker/container/portainer
docker compose up -d
```

---

## stackctl

Lightweight Bash tool to deploy, update, and stop multiple stacks from an interactive menu.

### Run Once

```bash
curl -sSL https://raw.githubusercontent.com/RAW-Network/homelab/main/stackctl.sh | bash
```

### Run from Repository

```bash
chmod +x stackctl.sh
./stackctl.sh
```

### Install System-Wide

```bash
curl -sSL https://raw.githubusercontent.com/RAW-Network/homelab/main/stackctl.sh -o ./stackctl.sh
chmod +x ./stackctl.sh
ln -s $(pwd)/stackctl.sh /usr/local/bin/stackctl
```

```bash
stackctl
```

To uninstall:

```bash
rm /usr/local/bin/stackctl
```

### Usage

```
1) DEPLOY STACK
2) UPDATE STACK
3) STOP STACK
4) EXIT
```

Selection supports `0` (all), comma-separated indices (`1,5,12`), or keywords (`portainer,jellyfin`).

---

## License

MIT — see [LICENSE](./LICENSE).