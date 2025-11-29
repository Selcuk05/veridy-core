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
forge script script/DeployVeridyMarketplace.s.sol:DeployVeridyMarketplace \
  --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast --verify
```

### Deploy to Mainnet

```bash
forge script script/DeployVeridyMarketplace.s.sol:DeployVeridyMarketplace \
  --rpc-url $MAINNET_RPC_URL --account deployer --broadcast --verify
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

### Predict Address

Run the script without `--broadcast` to see the predicted deployment address:

```bash
forge script script/DeployVeridyMarketplace.s.sol:DeployVeridyMarketplace --rpc-url $RPC_URL
```

## Contract Architecture

### VeridyMarketplace

- **initialize(address usdt)** - Set USDT token address (owner only, one-time)
- **createListing(...)** - Seller creates a data listing
- **purchaseListing(listingId, buyerPublicKey)** - Buyer deposits USDT in escrow
- **acceptPurchase(purchaseId, encK)** - Seller accepts and provides encrypted key
- **cancelPurchase(purchaseId)** - Buyer cancels and gets refund

### USDT Addresses

| Network | Address |
|---------|---------|
| Mainnet | `0xdAC17F958D2ee523a2206206994597C13D831ec7` |
| Sepolia | `0xd077A400968890Eacc75cdc901F0356c943e4fDb` |

## License

MIT
