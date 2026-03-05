# HP Verification Node Plugin

A verification node plugin for Humanity Protocol. It runs as a Docker container managed by interactive setup scripts, automatically processing on-chain verification tasks.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- A Humanity Protocol License NFT

## Quick Start

### One-Line Install (Recommended)

No need to clone the repo. Just run one command and follow the interactive wizard.

**macOS / Linux:**

```bash
curl -sSL https://github.com/humanity-org/hp-verification-node-plugin/releases/latest/download/start.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://github.com/humanity-org/hp-verification-node-plugin/releases/latest/download/start.ps1 | iex
```

**Windows (CMD):**

```cmd
powershell -Command "irm https://github.com/humanity-org/hp-verification-node-plugin/releases/latest/download/start.ps1 | iex"
```

### Passing Options

You can skip the interactive wizard by passing options directly:

**macOS / Linux:**

```bash
curl -sSL https://github.com/humanity-org/hp-verification-node-plugin/releases/latest/download/start.sh | bash -s -- --owner-address 0xYOUR_ADDRESS
```

**Windows (PowerShell):**

```powershell
& ([scriptblock]::Create((irm https://github.com/humanity-org/hp-verification-node-plugin/releases/latest/download/start.ps1))) --owner-address 0xYOUR_ADDRESS
```

### Available Options

| Option | Description |
|---|---|
| `--owner-address <address>` | License NFT holder's Ethereum address |
| `--private-key <key>` | Private key for transaction signing (without 0x prefix) |
| `--container-name <name>` | Custom container name (default: `hp-verification-node-plugin`) |
| `--restart` | Restart using saved config (skip setup wizard) |
| `-v, --verbose` | Enable debug-level logging |

### Run Locally

If you've already downloaded the scripts:

```bash
./start.sh
```

On Windows, double-click `start.cmd` or run:

```powershell
.\start.ps1
```

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
./start.sh --restart  # skip wizard, reuse saved config
```

## Troubleshooting

### Authentication Failures

- Verify private key is correctly configured
- Ensure verification API base URL is accessible

### Version Mismatch

If jobs are being skipped with "Node version too old" message, re-run the start script to pull the latest image.

## License

MIT
