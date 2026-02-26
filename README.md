# HP Verification Node Plugin

A containerized node that participates in the Humanity Protocol verification network. It runs as a Docker container and automatically processes on-chain verification tasks.

## Download

Download the latest release package from the [Releases page](https://github.com/humanity-org/hp-verification-node-plugin/releases/latest).

The zip file contains:
- `start.sh` — Start script for Linux / macOS
- `start.bat` — Start script for Windows
- `USER_MANUAL.md` — Full user manual

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- A License NFT (purchase from the link in Step 3)
- An Ethereum wallet with HP tokens to pay for gas fees when running the node

## Step-by-Step Guide

### Step 1 — Install Docker

Download and install Docker from https://docs.docker.com/get-docker/

### Step 2 — Run the Node

Ensure the node's address has sufficient HP token balance to pay for gas fees, then start the node:

```bash
# Linux / macOS
OWNER_ADDRESS=0xYourOwnerAddress ETH_PRIVATE_KEY=yourprivatekey ./start.sh -d

# Windows (Command Prompt)
set OWNER_ADDRESS=0xYourOwnerAddress & set ETH_PRIVATE_KEY=yourprivatekey & start.bat -d
```

> **Note:** The `-d` flag runs the container in detached (background) mode.

> **Note:** `ETH_PRIVATE_KEY` is optional (without `0x` prefix). If omitted, a new key will be generated automatically. You'll need to fund the new wallet with HP tokens.

### Step 3 — Purchase License NFT

Visit https://sale.staging.humanity.org/ and purchase a license.

### Step 4 — Bind License to Node

Visit https://humanity.delegate.easeflow.io/licenses and bind the license to your node's wallet address. After successful binding, the node will start processing verification tasks automatically.

### Step 5 — Check Logs

```bash
docker logs -f hp-verification-node-plugin
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OWNER_ADDRESS` | **Yes** | — | The Ethereum address that holds the License NFT |
| `ETH_PRIVATE_KEY` | No | Auto-generated | Private key for the node's wallet (without `0x` prefix). If not provided, a new key will be generated automatically |
| `CONTAINER_NAME` | No | `hp-verification-node-plugin` | Custom container name for running multiple instances |

## Running Multiple Instances

Use different `CONTAINER_NAME` values to run multiple nodes on the same machine:

```bash
CONTAINER_NAME=node-1 OWNER_ADDRESS=0xAddr1 ETH_PRIVATE_KEY=key1 ./start.sh -d
CONTAINER_NAME=node-2 OWNER_ADDRESS=0xAddr2 ETH_PRIVATE_KEY=key2 ./start.sh -d
```

Each instance requires its own License NFT and HP token balance.

## Common Commands

```bash
# View help and full guide
./start.sh -h

# Check container status
docker ps --filter name=hp-verification-node-plugin

# Follow logs
docker logs -f hp-verification-node-plugin

# Stop the node
docker stop hp-verification-node-plugin

# Update to latest version (just re-run the start script)
OWNER_ADDRESS=0xYourAddr ETH_PRIVATE_KEY=yourkey ./start.sh -d
```

## Documentation

A comprehensive `USER_MANUAL.md` is included in the release package with detailed instructions for all platforms, troubleshooting guide, and FAQ.

## License

MIT
