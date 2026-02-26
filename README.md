# HP Verification Node Plugin

A containerized node that participates in the Humanity Protocol verification network. It runs as a Docker container and automatically processes on-chain verification tasks.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- An Ethereum wallet holding a License NFT
- HP tokens for gas fees

## Quick Start

1. Download the latest release zip from the [Releases](https://github.com/humanity-org/hp-verification-node-plugin/releases) page
2. Extract the zip file
3. Run the start script with `-h` flag to view the complete step-by-step guide:

```bash
# Linux / macOS
./start.sh -h

# Windows (Command Prompt)
start.bat -h
```

The guide covers everything you need to get your node up and running — just follow the instructions.

4. Once ready, start the node:

```bash
# Linux / macOS
OWNER_ADDRESS=0xYourOwnerAddress ./start.sh -d

# Windows (Command Prompt)
set OWNER_ADDRESS=0xYourOwnerAddress & start.bat -d
```

## Documentation

A comprehensive `USER_MANUAL.md` is included in the release package, covering:

- Detailed setup instructions for Linux, macOS, and Windows
- Running multiple instances
- Environment variables reference
- Troubleshooting guide
- FAQ

## Support

If you encounter issues, review the container logs for detailed error messages:

```bash
docker logs -f hp-verification-node-plugin
```

## License

MIT
