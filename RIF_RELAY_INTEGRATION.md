# RIF Relay Batch Transactions Integration

This document explains how to integrate RIF Relay with the BlockBundlr batch transaction system, allowing users to pay gas fees with RIF tokens instead of rBTC.

## Overview

The integration provides:
- **Gas-less transactions**: Users pay with RIF tokens instead of rBTC
- **Batch optimization**: Multiple transactions bundled into one for gas efficiency
- **Smart wallet compatibility**: Works with RIF Relay Smart Wallets
- **Flexible payment**: Custom verifier for batch-specific token requirements

## Architecture

### Core Components

1. **RIFRelayBatchTransactions.sol**: Main contract that executes batch transactions and supports RIF Relay forwarding
2. **BatchTransactionVerifier.sol**: Custom verifier that validates token payments for batch transactions
3. **IRIFRelay.sol**: Interface definitions for RIF Relay integration
4. **Client Integration**: JavaScript examples for frontend integration

### How It Works

```
User → RIF Relay Client → Relay Server → Relay Hub → Smart Wallet → Batch Contract
  ↓
Pays RIF tokens for gas instead of rBTC
```

## Quick Start

### 1. Prerequisites

Ensure you have:
- RIF Relay contracts deployed (Hub, Verifiers, Smart Wallet Factory)
- RIF Relay Server running
- RIF tokens for gas payments

### 2. Deploy Contracts

```bash
# Deploy the batch contracts with RIF Relay support
forge script script/DeployRIFRelayBatch.s.sol --rpc-url $RPC_URL --broadcast
```

### 3. Configuration

After deployment, configure the contracts:

```solidity
// Add Smart Wallet Factory as trusted forwarder
batchContract.addTrustedForwarder(SMART_WALLET_FACTORY_ADDRESS);

// Accept RIF token in verifier
verifier.acceptToken(RIF_TOKEN_ADDRESS);
```

### 4. Client Integration

```javascript
const { RIFRelayBatchClient } = require('./examples/client-integration.js');

// Initialize client
const client = new RIFRelayBatchClient(config);
await client.initialize();

// Execute batch transactions
const transactions = [/* your transactions */];
await client.executeBatch(userAddress, transactions, rifTokenAmount);
```

## Contract Features

### RIFRelayBatchTransactions

**Key Features:**
- Compatible with both direct calls and RIF Relay forwarded calls
- Extracts original sender from relayed transactions
- Supports all original batch transaction methods
- Emits special events for relayed transactions

**Main Functions:**
```solidity
function executeBatch(Transaction[] calldata transactions, bool stopOnFailure) external payable
function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) external payable
function executeBatchWithGasLimits(...) external payable
```

**RIF Relay Functions:**
```solidity
function isTrustedForwarder(address forwarder) external view returns (bool)
function _msgSender() public view returns (address)
function _msgData() public view returns (bytes calldata)
```

### BatchTransactionVerifier

**Features:**
- Validates token payments for batch transactions
- Configurable minimum token amounts by batch size
- Supports multiple accepted tokens
- Gas limit validation

**Configuration:**
```solidity
function acceptToken(address token) external onlyOwner
function setMinTokenAmount(uint256 batchSize, uint256 amount) external onlyOwner
function setMaxBatchSize(uint256 newMaxSize) external onlyOwner
```

## Network Configurations

### Rootstock Testnet (Chain ID: 31)
```javascript
const testnetConfig = {
  chainId: 31,
  rifTokenAddress: '0x19F64674D8A5B4E652319F5e239eFd3bc969A1fE',
  smartWalletFactoryAddress: '0xCBc3BC24da96Ef5606d3801E13E1DC6E98C5c877',
  relayHubAddress: '0xAd525463961399793f8716b0D85133ff7503a7C2',
  deployVerifierAddress: '0xc67f193Bb1D64F13FD49E2da6586a2F417e56b16',
  relayVerifierAddress: '0xB86c972Ff212838C4c396199B27a0DBe45560df8'
};
```

### Rootstock Mainnet (Chain ID: 30)
```javascript
const mainnetConfig = {
  chainId: 30,
  rifTokenAddress: '0x2acc95758f8b5F583470bA265Eb685a8F45fC9D5',
  smartWalletFactoryAddress: '0x9EEbEC6C5157bEE13b451b1dfE1eE2cB40846323',
  relayHubAddress: '0x438Ce7f1FEC910588Be0fa0fAcD27D82De1DE0bC',
  deployVerifierAddress: '0x2FD633E358bc50Ccf6bf926D621E8612B55264C9',
  relayVerifierAddress: '0x5C9c7d96E6C59E55dA4dCf7F791AE58dAF8DBc86'
};
```

## Usage Examples

### Example 1: Batch ERC20 Transfers

```javascript
// Prepare transactions
const transactions = [
  {
    target: rifTokenAddress,
    value: 0,
    data: rifToken.interface.encodeFunctionData('transfer', [recipient1, amount1]),
    requireSuccess: true
  },
  {
    target: rifTokenAddress,
    value: 0,
    data: rifToken.interface.encodeFunctionData('transfer', [recipient2, amount2]),
    requireSuccess: true
  }
];

// Execute via RIF Relay (pays with RIF tokens)
await client.executeBatch(
  userAddress,
  transactions,
  ethers.utils.parseEther('5'), // 5 RIF tokens for gas
  false // Don't stop on failure
);
```

### Example 2: Batch ETH Transfers

```javascript
// Execute batch ETH transfers
await client.batchTransfer(
  userAddress,
  [recipient1, recipient2, recipient3],
  [
    ethers.utils.parseEther('0.01'),
    ethers.utils.parseEther('0.02'),
    ethers.utils.parseEther('0.015')
  ],
  ethers.utils.parseEther('3') // 3 RIF tokens for gas
);
```

### Example 3: Mixed Transaction Batch

```javascript
const mixedTransactions = [
  // ERC20 transfer
  {
    target: tokenAddress,
    value: 0,
    data: token.interface.encodeFunctionData('transfer', [recipient, amount]),
    requireSuccess: true
  },
  // Contract interaction
  {
    target: dappContractAddress,
    value: ethers.utils.parseEther('0.01'),
    data: dappContract.interface.encodeFunctionData('someFunction', [param1, param2]),
    requireSuccess: false
  },
  // Another contract call
  {
    target: anotherContractAddress,
    value: 0,
    data: anotherContract.interface.encodeFunctionData('anotherFunction', []),
    requireSuccess: true
  }
];

await client.executeBatch(userAddress, mixedTransactions, rifTokenAmount);
```

## Gas Cost Optimization

### Token Amount Calculation

The verifier uses tiered pricing for different batch sizes:

| Batch Size | Minimum RIF Tokens |
|------------|-------------------|
| 1          | 1 RIF             |
| 2-5        | 3 RIF             |
| 6-10       | 5 RIF             |
| 11-25      | 10 RIF            |
| 26-50      | 15 RIF            |

### Gas Estimation

```javascript
// Estimate gas for batch execution
const gasEstimate = await client.estimateBatchGas(transactions);
const rifTokensNeeded = await client.estimateTokenCost(gasEstimate);
```

## Smart Wallet Lifecycle

### 1. Generate Smart Wallet Address

```javascript
const smartWalletAddress = await getSmartWalletAddress(userAddress, index);
```

### 2. Deploy Smart Wallet (if needed)

```javascript
if (!smartWallet.isDeployed) {
  await client.deploySmartWallet(
    userAddress,
    ethers.utils.parseEther('1') // 1 RIF for deployment
  );
}
```

### 3. Fund Smart Wallet

```javascript
// Transfer RIF tokens to user's EOA
// Approve smart wallet to spend RIF tokens
await client.approveTokens(privateKey, ethers.utils.parseEther('100'));
```

### 4. Execute Transactions

```javascript
// Now ready to execute batch transactions
await client.executeBatch(userAddress, transactions, rifTokenAmount);
```

## Security Considerations

### Trusted Forwarders

Only add verified Smart Wallet Factory addresses as trusted forwarders:

```solidity
function addTrustedForwarder(address forwarder) external onlyOwner {
    require(isValidSmartWalletFactory(forwarder), "Invalid factory");
    _trustedForwarders[forwarder] = true;
}
```

### Token Validation

The verifier ensures:
- Token is in the accepted list
- User has sufficient balance
- Smart wallet has token allowance
- Gas limits are within bounds
- Request hasn't expired

### Reentrancy Protection

All batch functions use the `nonReentrant` modifier to prevent reentrancy attacks.

## Troubleshooting

### Common Issues

1. **"Token not accepted"**
   - Ensure the token is added to the verifier's accepted list
   - Check if you're using the correct token address

2. **"Insufficient token balance"**
   - User needs RIF tokens in their EOA
   - Check balance with `client.checkTokenStatus()`

3. **"Insufficient token allowance"**
   - Smart wallet needs approval to spend user's tokens
   - Call `client.approveTokens()` with sufficient amount

4. **"Smart wallet not deployed"**
   - Deploy the smart wallet first using `client.deploySmartWallet()`

5. **"Trusted forwarder not found"**
   - Add the Smart Wallet Factory as a trusted forwarder
   - Verify the factory address is correct

### Debug Functions

```javascript
// Check smart wallet status
const smartWallet = await client.getSmartWallet(userAddress);
console.log('Smart Wallet:', smartWallet);

// Check token allowances
const tokenStatus = await client.checkTokenStatus(userAddress);
console.log('Token Status:', tokenStatus);

// Verify forwarder
const isTrusted = await batchContract.isTrustedForwarder(smartWalletFactory);
console.log('Is Trusted Forwarder:', isTrusted);
```

## Integration Checklist

- [ ] Deploy RIF Relay contracts (Hub, Verifiers, Factory)
- [ ] Deploy batch transaction contracts
- [ ] Configure trusted forwarders
- [ ] Accept RIF token in verifier
- [ ] Set up RIF Relay Server
- [ ] Test smart wallet deployment
- [ ] Test token approvals
- [ ] Test batch transaction execution
- [ ] Verify gas cost optimization
- [ ] Set up monitoring and logging

## Gas Cost Comparison

### Traditional Approach
```
Transaction 1: 21,000 gas + overhead
Transaction 2: 21,000 gas + overhead
Transaction 3: 21,000 gas + overhead
Total: ~80,000+ gas (paid in rBTC)
```

### With RIF Relay Batch
```
Batch Transaction: ~65,000 gas (paid in RIF tokens)
Savings: ~20% gas + ability to pay with RIF tokens
```

## Future Enhancements

1. **Dynamic Pricing**: Adjust token amounts based on gas prices
2. **Multi-token Support**: Accept various tokens for gas payments
3. **Batch Size Optimization**: Auto-split large batches for optimal gas usage
4. **Integration with DeFi**: Direct integration with DEX aggregators
5. **Cross-chain Support**: Extend to other networks with similar relay systems

## Support

For issues and questions:
- Check the troubleshooting section
- Review RIF Relay documentation
- Open an issue in the repository
- Contact the development team

## License

MIT License - see LICENSE file for details.
