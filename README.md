# BatchTransactions Smart Contract for Rootstock

A comprehensive smart contract for executing batch transactions on the Rootstock blockchain. This contract allows you to execute multiple transactions in a single call, saving gas costs and simplifying complex operations.

## Features

- **Batch Execution**: Execute multiple transactions in a single call
- **Flexible Value Transfers**: Send ETH along with function calls
- **Gas Management**: Set individual gas limits for transactions
- **Error Handling**: Choose to stop on failure or continue execution
- **Access Control**: Owner and authorized executor system
- **Security**: Built-in reentrancy protection and pausable functionality
- **Batch Transfers**: Simplified ETH transfers to multiple recipients

## Contract Architecture

### Core Functions

1. **`executeBatch`**: Execute a batch of transactions with optional ETH transfers
2. **`executeBatchWithGasLimits`**: Execute batch with individual gas limits per transaction
3. **`batchTransfer`**: Simple ETH transfers to multiple recipients

### Security Features

- **Ownable**: Owner-only administrative functions
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Pausable**: Emergency pause functionality
- **Access Control**: Authorized executor system

### Configuration

- **Max Batch Size**: Configurable maximum number of transactions per batch (default: 50)
- **Max Gas Per Transaction**: Configurable gas limit per transaction (default: 500,000)

## Installation and Setup

### Prerequisites

- [Foundry](https://getfoundry.sh/) for development and testing
- Node.js and npm (optional, for additional tooling)

### Clone and Setup

```bash
git clone <your-repo>
cd rootstock-batch-transactions
forge install
```

### Compile

```bash
forge build
```

### Test

```bash
forge test
```

## Usage Examples

### Basic Batch Execution

```solidity
// Create transaction array
BatchTransactions.Transaction[] memory transactions = new BatchTransactions.Transaction[](2);

transactions[0] = BatchTransactions.Transaction({
    target: tokenAddress,
    value: 0,
    data: abi.encodeWithSignature("transfer(address,uint256)", recipient1, amount1),
    requireSuccess: true
});

transactions[1] = BatchTransactions.Transaction({
    target: tokenAddress,
    value: 0,
    data: abi.encodeWithSignature("transfer(address,uint256)", recipient2, amount2),
    requireSuccess: true
});

// Execute batch
batchContract.executeBatch(transactions, false);
```

### Batch ETH Transfers

```solidity
address[] memory recipients = new address[](3);
recipients[0] = address(0x123...);
recipients[1] = address(0x456...);
recipients[2] = address(0x789...);

uint256[] memory amounts = new uint256[](3);
amounts[0] = 1 ether;
amounts[1] = 2 ether;
amounts[2] = 0.5 ether;

// Send total amount with the call
batchContract.batchTransfer{value: 3.5 ether}(recipients, amounts);
```

### DeFi Operations Batch

```solidity
BatchTransactions.Transaction[] memory defiOps = new BatchTransactions.Transaction[](3);

// 1. Approve tokens
defiOps[0] = BatchTransactions.Transaction({
    target: tokenAddress,
    value: 0,
    data: abi.encodeWithSignature("approve(address,uint256)", dexAddress, tokenAmount),
    requireSuccess: true
});

// 2. Swap tokens
defiOps[1] = BatchTransactions.Transaction({
    target: dexAddress,
    value: 0,
    data: abi.encodeWithSignature("swapExactTokensForETH(...)", ...),
    requireSuccess: true
});

// 3. Stake received ETH
defiOps[2] = BatchTransactions.Transaction({
    target: stakingContract,
    value: 1 ether,
    data: abi.encodeWithSignature("stake()"),
    requireSuccess: false // Allow this to fail
});

batchContract.executeBatch{value: 1 ether}(defiOps, false);
```

## Deployment

### Using Foundry Scripts

1. Set up your environment variables:

```bash
export PRIVATE_KEY="your_private_key"
export RPC_URL="https://rpc.rootstock.io/your-api-key"
```

2. Deploy to Rootstock Mainnet:

```bash
forge script script/DeployBatchTransactions.s.sol:DeployBatchTransactions --rpc-url $RPC_URL --broadcast
```

3. Deploy with custom configuration:

```bash
export MAX_BATCH_SIZE=30
export MAX_GAS_PER_TX=400000
forge script script/DeployBatchTransactions.s.sol:DeployAndConfigureBatchTransactions --rpc-url $RPC_URL --broadcast
```

### Verify Deployment

```bash
export CONTRACT_ADDRESS="deployed_contract_address"
forge script script/DeployBatchTransactions.s.sol:VerifyBatchTransactions --rpc-url $RPC_URL
```

## API Reference

### Structs

#### `Transaction`

```solidity
struct Transaction {
    address target;      // Target contract address
    uint256 value;       // ETH value to send
    bytes data;          // Call data
    bool requireSuccess; // Whether to revert if this transaction fails
}
```

#### `BatchResult`

```solidity
struct BatchResult {
    bool success;        // Whether the transaction succeeded
    bytes returnData;    // Return data from the call
    uint256 gasUsed;     // Gas used by the transaction
}
```

### Main Functions

#### `executeBatch(Transaction[] transactions, bool stopOnFailure)`

Execute a batch of transactions.

- `transactions`: Array of transactions to execute
- `stopOnFailure`: Whether to stop execution if any transaction fails
- Returns: Array of `BatchResult`

#### `executeBatchWithGasLimits(Transaction[] transactions, uint256[] gasLimits, bool stopOnFailure)`

Execute batch with individual gas limits per transaction.

#### `batchTransfer(address[] recipients, uint256[] amounts)`

Execute simple ETH transfers to multiple recipients.

### Administrative Functions

#### `authorizeExecutor(address executor)`

Authorize an address to execute batches (owner only).

#### `revokeExecutor(address executor)`

Revoke authorization for an address (owner only).

#### `setMaxBatchSize(uint256 newMaxBatchSize)`

Set maximum batch size (owner only).

#### `setMaxGasPerTransaction(uint256 newMaxGas)`

Set maximum gas per transaction (owner only).

#### `pause()` / `unpause()`

Pause/unpause contract functionality (owner only).

## Security Considerations

1. **Access Control**: Only authorized addresses can execute batches
2. **Reentrancy Protection**: Built-in protection against reentrancy attacks
3. **Gas Limits**: Configurable gas limits prevent DoS attacks
4. **Pausable**: Emergency pause functionality for security incidents
5. **Error Handling**: Robust error handling with optional failure tolerance

## Gas Optimization

- Batch multiple transactions to save on base transaction costs
- Use `requireSuccess: false` for optional transactions
- Consider gas limits when batching many operations
- ETH refunds for excess value sent

## Rootstock Specific Considerations

- Compatible with Rootstock's EVM implementation
- Gas costs similar to Ethereum mainnet
- Supports all standard Ethereum tooling (Foundry, Hardhat, etc.)
- Can interact with any ERC-20 tokens or smart contracts on Rootstock

## Testing

The contract includes comprehensive tests covering:

- Basic batch execution
- Error handling scenarios
- Access control
- Gas limit enforcement
- ETH transfers and refunds
- Pause/unpause functionality

Run tests with:

```bash
forge test -v
```

For gas reports:

```bash
forge test --gas-report
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Support

For questions or issues:

- Create an issue on GitHub
- Review the test files for usage examples
- Check the example contracts in the `example/` directory