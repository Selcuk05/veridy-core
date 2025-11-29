# Veridy Marketplace

Veridy is a decentralized data marketplace, where users can sell data to be bought with USDT by people, companies and other third parties. This repository contains of the core smart contract of the Veridy marketplace, as well as the deployment and test scripts.

## Overview

Veridy utilises Tether WDK for its wallet infrastructure. This allows easy onboarding for both newcomers and crypto-native users. On Veridy, users can sell many types of data (including tabular, image, audio and many others...) to those who are in need of specific, domain-focused data for their research, work, and such other activities. 

## Quick Start

```bash
# Build
forge build

# Test
forge test

# Format
forge fmt
```

### Setup (one-time)

Import your deployer account into Foundry's secure keystore:

```bash
cast wallet import deployer --interactive
```

### Deploy to Sepolia

```bash
forge script script/DeployVeridyMarketplace.s.sol:DeployVeridyMarketplace --rpc-url sepolia --account deployer --broadcast
```

### Deploy to Arbitrum

```bash
forge script script/DeployVeridyMarketplace.s.sol:DeployVeridyMarketplace --rpc-url arbitrum --account deployer --broadcast
```

### Local Development

Start Anvil and deploy with mock USDT:

```bash
# Terminal 1
anvil

# Terminal 2
forge script script/DeployVeridyMarketplace.s.sol:DeployVeridyMarketplaceLocal \
  --rpc-url http://localhost:8545 --broadcast
```

## Contract Architecture

### VeridyMarketplace

- **initialize(address usdt)** - Set USDT token address (owner only, one-time)
- **createListing(...)** - Seller creates a data listing
- **purchaseListing(listingId, buyerPublicKey)** - Buyer deposits USDT in escrow
- **acceptPurchase(purchaseId, encK)** - Seller accepts and provides encrypted key
- **cancelPurchase(purchaseId)** - Buyer cancels and gets refund

### Deployment addresses

| Network | Address |
|---------|---------|
| Arbitrum | `0xD3A17B869883EAec005620D84B38E68d3c6cF893` |
| Sepolia | `0x57b721a1904fb5187b93857f7f38fba80b568f34` |

## License

MIT
