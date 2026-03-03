# HP Verification Node Plugin

A containerized node that participates in the Humanity Protocol verification network. It runs as a Docker container and automatically processes on-chain verification tasks.

## Download

Download the latest release package from the [Releases page](https://github.com/humanity-org/hp-verification-node-plugin/releases/latest).

The zip file contains:
- `start.sh` — Start script for Linux / macOS (interactive setup wizard)
- `start.bat` — Start script for Windows
- `USER_MANUAL.md` — Full user manual

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- A License NFT (purchase from https://sale.staging.humanity.org/)
- An Ethereum wallet with HP tokens to pay for gas fees when running the node

## Quick Start

### Linux / macOS

Simply run the start script — it includes an interactive setup wizard that will guide you through every step:

```bash
chmod +x start.sh
./start.sh
```

The wizard walks you through:
1. **Checking prerequisites** — verifies Docker is installed and running
2. **Naming your node** — set a custom name (useful for multiple instances)
3. **License owner address** — the wallet holding your License NFT
4. **Node wallet** — use your own key or auto-generate a new one
5. **Review & launch** — confirm settings and start the node

You can also skip the wizard by passing arguments directly:

```bash
# Skip specific wizard steps with CLI arguments
./start.sh --owner-address 0x1234...abcd
./start.sh --owner-address 0x1234... --private-key abcd1234...
./start.sh --owner-address 0x1234... --container-name my-node

# Or use environment variables for fully non-interactive mode
OWNER_ADDRESS=0x1234... ETH_PRIVATE_KEY=abcd1234... ./start.sh
```

### Windows

```cmd
set OWNER_ADDRESS=0xYourOwnerAddress
start.bat
```

Or with a custom private key:

```cmd
set OWNER_ADDRESS=0x1234...abcd
set ETH_PRIVATE_KEY=abcd1234...ef56
start.bat
```

> **Note:** `ETH_PRIVATE_KEY` is optional (without `0x` prefix). If not provided, a new key will be generated automatically.

## After Starting the Node

1. **Find your node's wallet address** (if auto-generated):
   ```bash
   docker logs hp-verification-node-plugin 2>&1 | head -20
   ```
2. **Fund the wallet** with HP tokens for gas fees
3. **Purchase a License NFT** at https://sale.staging.humanity.org/
4. **Bind the license** to your node's wallet at https://humanity.delegate.easeflow.io/licenses

Once the license is bound, the node will automatically start processing verification tasks.

## Running Multiple Instances

Run the wizard multiple times with different node names, or use CLI arguments:

```bash
./start.sh --owner-address 0xAddr1 --private-key key1 --container-name node-1
./start.sh --owner-address 0xAddr2 --private-key key2 --container-name node-2
```

Each instance requires its own License NFT and HP token balance.

## Common Commands

```bash
# View help
./start.sh -h

# Check container status
docker ps --filter name=hp-verification-node-plugin

# Follow logs
docker logs -f hp-verification-node-plugin

# Stop the node
docker stop hp-verification-node-plugin

# Restart / update to latest version (just re-run the start script)
./start.sh
```

## Documentation

A comprehensive `USER_MANUAL.md` is included in the release package with detailed instructions for all platforms, troubleshooting guide, and FAQ.

## License

MIT
