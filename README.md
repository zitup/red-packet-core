# Crypto Red Packet

A decentralized and customizable red packet (红包) system built on blockchain technology. This project combines traditional red packet culture with modern blockchain features, offering a flexible and secure way to distribute tokens and NFTs.

<!-- Dapp page: https://bless3.vercel.app/, mainly developed by AI. -->

## Key Features

### Flexible Asset Support

- Support for multiple asset types:
  - Native tokens (ETH)
  - ERC20 tokens
  - ERC721 NFTs
  - ERC1155 NFTs
- Multiple assets can be included in a single red packet

### Advanced Distribution Rules

- Fixed distribution: Equal amounts for all recipients
- Random distribution: Random amounts with customizable minimum values
- Support for future distribution strategies through modular design

### Customizable Access Control

- Code-based access: Recipients need a specific code to claim
- Token holder access: Only holders of specific tokens can claim
- Whitelist access: Only whitelisted addresses can claim
- Lucky draw access: Random chance to claim based on probability
- Generic access: Custom validation logic through smart contracts

### Trigger Conditions

- Price triggers: Only claimable when token price meets conditions
- State triggers: Claimable based on contract state
- Extensible trigger system for custom conditions

### Security Features

- Permit2 integration for gasless token approvals
- Beacon proxy pattern for upgradability
- Comprehensive access control and validation
- Reentrancy protection

## Technical Architecture

### Core Contracts

- `RedPacketFactory.sol`: Main factory for creating and managing red packets
- `RedPacket.sol`: Implementation of red packet logic
- Various validator contracts for access control and triggers

### Components

- Access Control System
- Trigger System
- Distribution System
- Asset Management System

## Development

### Prerequisites

- Foundry toolkit
- Node.js and npm/yarn
- Git

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy

```shell
$ forge script script/deploy.s.sol:Deploy --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Security

- Under development, not thoroughly tested

## License

BUSL-1.1
