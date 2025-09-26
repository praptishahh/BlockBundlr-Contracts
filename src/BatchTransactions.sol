// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title BatchTransactions
 * @dev Smart contract for executing batch transactions on Rootstock
 * @author Your Name
 */
contract BatchTransactions {
    
    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    // Pausable functionality
    bool private _paused;
    
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
    
    // Administrative functions removed - contract is now ownerless
    
    // Pausable functions
    function paused() public view returns (bool) {
        return _paused;
    }
    
    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }
    
    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
    
    // Events
    event BatchExecuted(address indexed executor, uint256 batchId, uint256 successCount, uint256 totalCount);
    event TransactionExecuted(address indexed target, uint256 value, bool success, bytes returnData);
    event TransactionFailed(address indexed target, uint256 value, string reason);
    event FundsWithdrawn(address indexed to, uint256 amount);
    
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
    mapping(address => bool) public authorizedExecutors;
    mapping(uint256 => address) public batchExecutors;
    
    // Modifiers
    modifier onlyAuthorized() {
        require(authorizedExecutors[msg.sender], "Not authorized");
        _;
    }
    
    modifier validBatchSize(uint256 size) {
        require(size > 0 && size <= maxBatchSize, "Invalid batch size");
        _;
    }
    
    constructor() {
        _status = _NOT_ENTERED;
        authorizedExecutors[msg.sender] = true;
    }
    
    /**
     * @dev Execute a batch of transactions
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
        onlyAuthorized 
        validBatchSize(transactions.length)
        returns (BatchResult[] memory results) 
    {
        uint256 batchId = ++batchCounter;
        batchExecutors[batchId] = msg.sender;
        
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
        
        emit BatchExecuted(msg.sender, batchId, successCount, transactions.length);
        
        // Refund excess ETH
        if (msg.value > totalValue) {
            payable(msg.sender).transfer(msg.value - totalValue);
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
        onlyAuthorized 
        validBatchSize(transactions.length)
        returns (BatchResult[] memory results) 
    {
        require(transactions.length == gasLimits.length, "Array length mismatch");
        
        uint256 batchId = ++batchCounter;
        batchExecutors[batchId] = msg.sender;
        
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
        
        emit BatchExecuted(msg.sender, batchId, successCount, transactions.length);
        
        // Refund excess ETH
        if (msg.value > totalValue) {
            payable(msg.sender).transfer(msg.value - totalValue);
        }
        
        return results;
    }
    
    /**
     * @dev Execute simple batch transfers (ETH only)
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
        onlyAuthorized 
        validBatchSize(recipients.length)
        returns (bool[] memory success) 
    {
        require(recipients.length == amounts.length, "Array length mismatch");
        
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
            payable(msg.sender).transfer(msg.value - totalAmount);
        }
        
        return success;
    }
    
    // Administrative functions removed - contract is now ownerless and immutable
    // Authorization can only be set during deployment in the constructor
    
    /**
     * @dev Get contract balance
     * @return balance Current ETH balance of the contract
     */
    function getBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }
    
    /**
     * @dev Check if address is authorized
     * @param executor Address to check
     * @return authorized Whether the address is authorized
     */
    function isAuthorized(address executor) external view returns (bool authorized) {
        return authorizedExecutors[executor];
    }
    
    // Fallback function to receive ETH
    receive() external payable {}
    
    // Fallback function for unknown function calls
    fallback() external payable {}
}
