// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./interfaces/IRIFRelay.sol";

/**
 * @title RIFRelayBatchTransactions
 * @dev Smart contract for executing batch transactions with RIF Relay support
 * Allows users to pay gas fees with RIF tokens instead of rBTC
 * @author BlockBundlr Team
 */
contract RIFRelayBatchTransactions is IRelayRecipient {
    
    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    // Pausable functionality
    bool private _paused;
    
    // RIF Relay trusted forwarders (Smart Wallet Factory addresses)
    mapping(address => bool) private _trustedForwarders;
    
    // Owner for administrative functions
    address public owner;
    
    // Events and modifiers
    
    // Reentrancy guard modifiers
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    // Pausable events and modifiers
    event Paused(address account);
    event Unpaused(address account);
    
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }
    
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }
    
    // Pausable functions
    function paused() public view returns (bool) {
        return _paused;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }
    
    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
    
    // Events
    event BatchExecuted(address indexed executor, uint256 batchId, uint256 successCount, uint256 totalCount);
    event TransactionExecuted(address indexed target, uint256 value, bool success, bytes returnData);
    event TransactionFailed(address indexed target, uint256 value, string reason);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event TrustedForwarderAdded(address indexed forwarder);
    event TrustedForwarderRemoved(address indexed forwarder);
    event RelayedBatchExecuted(address indexed smartWallet, address indexed originalSender, uint256 batchId);
    
    // Structs
    struct Transaction {
        address target;      // Target contract address
        uint256 value;       // ETH value to send
        bytes data;          // Call data
        bool requireSuccess; // Whether to revert if this transaction fails
    }
    
    struct BatchResult {
        bool success;
        bytes returnData;
        uint256 gasUsed;
    }
    
    // State variables
    uint256 public batchCounter;
    uint256 public maxBatchSize = 50; // Maximum number of transactions per batch
    uint256 public maxGasPerTransaction = 500000; // Maximum gas per transaction
    
    // Mappings
    mapping(uint256 => address) public batchExecutors;
    
    modifier validBatchSize(uint256 size) {
        require(size > 0 && size <= maxBatchSize, "Invalid batch size");
        _;
    }
    
    constructor(address _owner) {
        require(_owner != address(0), "Invalid owner address");
        _status = _NOT_ENTERED;
        owner = _owner;
    }
    
    // ===== RIF Relay Integration Functions =====
    
    /**
     * @dev Add a trusted forwarder (Smart Wallet Factory)
     * @param forwarder Address of the forwarder to trust
     */
    function addTrustedForwarder(address forwarder) external onlyOwner {
        require(forwarder != address(0), "Invalid forwarder address");
        _trustedForwarders[forwarder] = true;
        emit TrustedForwarderAdded(forwarder);
    }
    
    /**
     * @dev Remove a trusted forwarder
     * @param forwarder Address of the forwarder to remove
     */
    function removeTrustedForwarder(address forwarder) external onlyOwner {
        _trustedForwarders[forwarder] = false;
        emit TrustedForwarderRemoved(forwarder);
    }
    
    /**
     * @dev Check if an address is a trusted forwarder
     * @param forwarder Address to check
     * @return bool True if trusted forwarder
     */
    function isTrustedForwarder(address forwarder) public view override returns (bool) {
        return _trustedForwarders[forwarder];
    }
    
    /**
     * @dev Get the original sender of the transaction (works with both direct and relayed calls)
     * @return sender Original sender address
     */
    function _msgSender() public view override returns (address sender) {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            // Extract the original sender from the last 20 bytes of msg.data (RIF Relay pattern)
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }
    
    /**
     * @dev Get the original msg.data (works with both direct and relayed calls)
     * @return data Original call data
     */
    function _msgData() public view override returns (bytes calldata data) {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            // Remove the last 20 bytes (sender address) from msg.data
            return msg.data[:msg.data.length - 20];
        } else {
            return msg.data;
        }
    }
    
    // ===== Batch Transaction Functions =====
    
    /**
     * @dev Execute a batch of transactions (RIF Relay compatible)
     * @param transactions Array of transactions to execute
     * @param stopOnFailure Whether to stop execution if any transaction fails
     * @return results Array of batch results
     */
    function executeBatch(
        Transaction[] calldata transactions,
        bool stopOnFailure
    ) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        validBatchSize(transactions.length)
        returns (BatchResult[] memory results) 
    {
        address originalSender = _msgSender();
        uint256 batchId = ++batchCounter;
        batchExecutors[batchId] = originalSender;
        
        results = new BatchResult[](transactions.length);
        uint256 successCount = 0;
        uint256 totalValue = 0;
        
        // Calculate total value needed
        for (uint256 i = 0; i < transactions.length; i++) {
            totalValue += transactions[i].value;
        }
        
        require(msg.value >= totalValue, "Insufficient ETH sent");
        
        // Execute transactions
        for (uint256 i = 0; i < transactions.length; i++) {
            Transaction calldata txn = transactions[i];
            
            // Validate target address
            require(txn.target != address(0), "Invalid target address");
            
            uint256 gasStart = gasleft();
            
            try this.executeTransaction{value: txn.value}(
                txn.target,
                txn.value,
                txn.data
            ) returns (bytes memory returnData) {
                results[i] = BatchResult({
                    success: true,
                    returnData: returnData,
                    gasUsed: gasStart - gasleft()
                });
                successCount++;
                
                emit TransactionExecuted(txn.target, txn.value, true, returnData);
                
            } catch Error(string memory reason) {
                results[i] = BatchResult({
                    success: false,
                    returnData: bytes(reason),
                    gasUsed: gasStart - gasleft()
                });
                
                emit TransactionFailed(txn.target, txn.value, reason);
                
                if (txn.requireSuccess || stopOnFailure) {
                    revert(string(abi.encodePacked("Transaction failed: ", reason)));
                }
                
            } catch (bytes memory lowLevelData) {
                results[i] = BatchResult({
                    success: false,
                    returnData: lowLevelData,
                    gasUsed: gasStart - gasleft()
                });
                
                emit TransactionFailed(txn.target, txn.value, "Low-level call failed");
                
                if (txn.requireSuccess || stopOnFailure) {
                    revert("Transaction failed: Low-level call failed");
                }
            }
        }
        
        emit BatchExecuted(originalSender, batchId, successCount, transactions.length);
        
        // Emit special event for relayed transactions
        if (isTrustedForwarder(msg.sender)) {
            emit RelayedBatchExecuted(msg.sender, originalSender, batchId);
        }
        
        // Refund excess ETH
        if (msg.value > totalValue) {
            payable(originalSender).transfer(msg.value - totalValue);
        }
        
        return results;
    }
    
    /**
     * @dev Execute a single transaction (used internally for better error handling)
     * @param target Target contract address
     * @param value ETH value to send
     * @param data Call data
     * @return returnData Return data from the call
     */
    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory returnData) {
        require(msg.sender == address(this), "Only callable by this contract");
        
        (bool success, bytes memory result) = target.call{value: value}(data);
        
        if (!success) {
            // Try to extract revert reason
            if (result.length > 0) {
                assembly {
                    let returndata_size := mload(result)
                    revert(add(32, result), returndata_size)
                }
            } else {
                revert("Transaction execution failed");
            }
        }
        
        return result;
    }
    
    /**
     * @dev Execute batch with different gas limits per transaction
     * @param transactions Array of transactions to execute
     * @param gasLimits Array of gas limits for each transaction
     * @param stopOnFailure Whether to stop execution if any transaction fails
     * @return results Array of batch results
     */
    function executeBatchWithGasLimits(
        Transaction[] calldata transactions,
        uint256[] calldata gasLimits,
        bool stopOnFailure
    ) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        validBatchSize(transactions.length)
        returns (BatchResult[] memory results) 
    {
        require(transactions.length == gasLimits.length, "Array length mismatch");
        
        address originalSender = _msgSender();
        uint256 batchId = ++batchCounter;
        batchExecutors[batchId] = originalSender;
        
        results = new BatchResult[](transactions.length);
        uint256 successCount = 0;
        uint256 totalValue = 0;
        
        // Calculate total value needed
        for (uint256 i = 0; i < transactions.length; i++) {
            totalValue += transactions[i].value;
            require(gasLimits[i] <= maxGasPerTransaction, "Gas limit too high");
        }
        
        require(msg.value >= totalValue, "Insufficient ETH sent");
        
        // Execute transactions with specific gas limits
        for (uint256 i = 0; i < transactions.length; i++) {
            Transaction calldata txn = transactions[i];
            
            require(txn.target != address(0), "Invalid target address");
            
            uint256 gasStart = gasleft();
            
            (bool success, bytes memory returnData) = txn.target.call{
                value: txn.value,
                gas: gasLimits[i]
            }(txn.data);
            
            results[i] = BatchResult({
                success: success,
                returnData: returnData,
                gasUsed: gasStart - gasleft()
            });
            
            if (success) {
                successCount++;
                emit TransactionExecuted(txn.target, txn.value, true, returnData);
            } else {
                emit TransactionFailed(txn.target, txn.value, "Transaction failed");
                
                if (txn.requireSuccess || stopOnFailure) {
                    revert("Required transaction failed");
                }
            }
        }
        
        emit BatchExecuted(originalSender, batchId, successCount, transactions.length);
        
        // Emit special event for relayed transactions
        if (isTrustedForwarder(msg.sender)) {
            emit RelayedBatchExecuted(msg.sender, originalSender, batchId);
        }
        
        // Refund excess ETH
        if (msg.value > totalValue) {
            payable(originalSender).transfer(msg.value - totalValue);
        }
        
        return results;
    }
    
    /**
     * @dev Execute simple batch transfers (ETH only) - RIF Relay compatible
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send
     * @return success Array indicating success for each transfer
     */
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        validBatchSize(recipients.length)
        returns (bool[] memory success) 
    {
        require(recipients.length == amounts.length, "Array length mismatch");
        
        address originalSender = _msgSender();
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        require(msg.value >= totalAmount, "Insufficient ETH sent");
        
        success = new bool[](recipients.length);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            
            (bool sent, ) = recipients[i].call{value: amounts[i]}("");
            success[i] = sent;
            
            if (sent) {
                emit TransactionExecuted(recipients[i], amounts[i], true, "");
            } else {
                emit TransactionFailed(recipients[i], amounts[i], "Transfer failed");
            }
        }
        
        // Refund excess ETH
        if (msg.value > totalAmount) {
            payable(originalSender).transfer(msg.value - totalAmount);
        }
        
        return success;
    }
    
    // ===== Administrative Functions =====
    
    /**
     * @dev Update max batch size
     * @param newMaxBatchSize New maximum batch size
     */
    function setMaxBatchSize(uint256 newMaxBatchSize) external onlyOwner {
        require(newMaxBatchSize > 0 && newMaxBatchSize <= 100, "Invalid batch size");
        maxBatchSize = newMaxBatchSize;
    }
    
    /**
     * @dev Update max gas per transaction
     * @param newMaxGas New maximum gas per transaction
     */
    function setMaxGasPerTransaction(uint256 newMaxGas) external onlyOwner {
        require(newMaxGas > 0, "Invalid gas limit");
        maxGasPerTransaction = newMaxGas;
    }
    
    /**
     * @dev Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }
    
    /**
     * @dev Get contract balance
     * @return balance Current ETH balance of the contract
     */
    function getBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }
    
    /**
     * @dev Emergency withdraw function (only owner)
     * @param to Address to send funds to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount <= address(this).balance, "Insufficient balance");
        
        to.transfer(amount);
        emit FundsWithdrawn(to, amount);
    }
    
    // Fallback function to receive ETH
    receive() external payable {}
    
    // Fallback function for unknown function calls
    fallback() external payable {}
}