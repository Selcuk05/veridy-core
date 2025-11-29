# Veridy Marketplace

A decentralized data marketplace for selling encrypted files stored on IPFS. Uses ECDH for secure key exchange between sellers and buyers.

## Overview

Sellers upload encrypted files to IPFS and list them on the marketplace. Buyers purchase listings by depositing USDT in escrow. When the seller accepts, they provide the encrypted decryption key and receive payment.

## Quick Start

```bash
# Build
forge build

# Test
forge test

# Format
forge fmt
```

## Deployment

Uses CREATE2 for deterministic addresses (same address on all chains).

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
