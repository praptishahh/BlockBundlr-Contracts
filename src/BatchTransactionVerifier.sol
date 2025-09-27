// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IRIFRelay.sol";

/**
 * @title BatchTransactionVerifier
 * @dev Custom verifier for RIF Relay batch transactions
 * Validates token payments and batch transaction requirements
 */
contract BatchTransactionVerifier is IRelayVerifier {
    
    // Version identifier
    string private constant VERSION = "2.0.1";
    
    // Owner of the verifier (can manage accepted tokens and settings)
    address public owner;
    
    // Accepted tokens for relay payment
    mapping(address => bool) public acceptedTokens;
    
    // Minimum token amounts required for different batch sizes
    mapping(uint256 => uint256) public minTokenAmountByBatchSize;
    
    // Maximum batch size allowed
    uint256 public maxBatchSize = 50;
    
    // Events
    event TokenAccepted(address indexed token);
    event TokenRejected(address indexed token);
    event MinTokenAmountSet(uint256 indexed batchSize, uint256 amount);
    event MaxBatchSizeUpdated(uint256 newMaxSize);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }
    
    constructor(address _owner) {
        require(_owner != address(0), "Invalid owner address");
        owner = _owner;
        
        // Set default minimum token amounts for different batch sizes
        minTokenAmountByBatchSize[1] = 1e18;   // 1 token for single transaction
        minTokenAmountByBatchSize[5] = 3e18;   // 3 tokens for up to 5 transactions
        minTokenAmountByBatchSize[10] = 5e18;  // 5 tokens for up to 10 transactions
        minTokenAmountByBatchSize[25] = 10e18; // 10 tokens for up to 25 transactions
        minTokenAmountByBatchSize[50] = 15e18; // 15 tokens for up to 50 transactions
    }
    
    /**
     * @dev Check if a token is accepted for relay payments
     * @param token Token address to check
     * @return bool True if token is accepted
     */
    function acceptsToken(address token) external view override returns (bool) {
        return acceptedTokens[token];
    }
    
    /**
     * @dev Get the verifier version
     * @return string Version identifier
     */
    function versionVerifier() external pure override returns (string memory) {
        return VERSION;
    }
    
    /**
     * @dev Accept a token for relay payments
     * @param token Token address to accept
     */
    function acceptToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        acceptedTokens[token] = true;
        emit TokenAccepted(token);
    }
    
    /**
     * @dev Reject a token for relay payments
     * @param token Token address to reject
     */
    function rejectToken(address token) external onlyOwner {
        acceptedTokens[token] = false;
        emit TokenRejected(token);
    }
    
    /**
     * @dev Set minimum token amount for a specific batch size
     * @param batchSize Batch size threshold
     * @param amount Minimum token amount required
     */
    function setMinTokenAmount(uint256 batchSize, uint256 amount) external onlyOwner {
        require(batchSize > 0 && batchSize <= maxBatchSize, "Invalid batch size");
        require(amount > 0, "Amount must be positive");
        
        minTokenAmountByBatchSize[batchSize] = amount;
        emit MinTokenAmountSet(batchSize, amount);
    }
    
    /**
     * @dev Set maximum allowed batch size
     * @param newMaxSize New maximum batch size
     */
    function setMaxBatchSize(uint256 newMaxSize) external onlyOwner {
        require(newMaxSize > 0 && newMaxSize <= 100, "Invalid max batch size");
        maxBatchSize = newMaxSize;
        emit MaxBatchSizeUpdated(newMaxSize);
    }
    
    /**
     * @dev Get minimum token amount required for a specific batch size
     * @param batchSize Number of transactions in the batch
     * @return uint256 Minimum token amount required
     */
    function getMinTokenAmount(uint256 batchSize) external view returns (uint256) {
        if (batchSize == 0) return 0;
        
        // Find the appropriate tier
        if (batchSize == 1) return minTokenAmountByBatchSize[1];
        if (batchSize <= 5) return minTokenAmountByBatchSize[5];
        if (batchSize <= 10) return minTokenAmountByBatchSize[10];
        if (batchSize <= 25) return minTokenAmountByBatchSize[25];
        if (batchSize <= 50) return minTokenAmountByBatchSize[50];
        
        // For larger batches, calculate proportionally
        return minTokenAmountByBatchSize[50] * batchSize / 50;
    }
    
    /**
     * @dev Validate a relay request for batch transactions
     * @param request The forward request to validate
     * @param signature The signature of the request
     * @return success True if validation passes
     * @return revertReason Reason for failure if validation fails
     */
    function validateRelayRequest(
        ForwardRequest calldata request,
        bytes calldata signature
    ) external view returns (bool success, string memory revertReason) {
        // Check if token is accepted
        if (!acceptedTokens[request.tokenContract]) {
            return (false, "Token not accepted");
        }
        
        // Check token amount (basic validation - more sophisticated logic can be added)
        if (request.tokenAmount == 0) {
            return (false, "Token amount cannot be zero");
        }
        
        // Check if user has sufficient token balance
        IERC20 token = IERC20(request.tokenContract);
        if (token.balanceOf(request.from) < request.tokenAmount) {
            return (false, "Insufficient token balance");
        }
        
        // Check token allowance to the smart wallet
        if (token.allowance(request.from, request.to) < request.tokenAmount) {
            return (false, "Insufficient token allowance");
        }
        
        // Validate gas limits
        if (request.gas > 5000000) { // 5M gas limit
            return (false, "Gas limit too high");
        }
        
        if (request.tokenGas > 100000) { // 100k gas for token transfer
            return (false, "Token gas limit too high");
        }
        
        // Check expiration
        if (request.validUntilTime != 0 && request.validUntilTime < block.timestamp) {
            return (false, "Request expired");
        }
        
        // Additional validation based on call data can be added here
        // For example, decode the batch size from the call data and validate token amount
        
        return (true, "");
    }
    
    /**
     * @dev Validate a deploy request for smart wallet deployment
     * @param request The forward request to validate
     * @return success True if validation passes
     * @return revertReason Reason for failure if validation fails
     */
    function validateDeployRequest(
        ForwardRequest calldata request
    ) external view returns (bool success, string memory revertReason) {
        // Check if token is accepted
        if (!acceptedTokens[request.tokenContract]) {
            return (false, "Token not accepted");
        }
        
        // For deploy requests, we might want lower minimum amounts
        uint256 minAmount = minTokenAmountByBatchSize[1]; // Use single transaction minimum
        if (request.tokenAmount < minAmount) {
            return (false, "Insufficient token amount for deployment");
        }
        
        // Check if user has sufficient token balance
        IERC20 token = IERC20(request.tokenContract);
        if (token.balanceOf(request.from) < request.tokenAmount) {
            return (false, "Insufficient token balance");
        }
        
        // Validate gas limits for deployment
        if (request.gas > 1000000) { // 1M gas limit for deployment
            return (false, "Gas limit too high for deployment");
        }
        
        // Check expiration
        if (request.validUntilTime != 0 && request.validUntilTime < block.timestamp) {
            return (false, "Deploy request expired");
        }
        
        return (true, "");
    }
    
    /**
     * @dev Transfer ownership to a new owner
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @dev Check if the verifier supports a specific feature
     * @param feature Feature identifier
     * @return bool True if feature is supported
     */
    function supportsFeature(bytes32 feature) external pure returns (bool) {
        // Define feature flags
        bytes32 BATCH_TRANSACTIONS = keccak256("BATCH_TRANSACTIONS");
        bytes32 TOKEN_VALIDATION = keccak256("TOKEN_VALIDATION");
        bytes32 GAS_ESTIMATION = keccak256("GAS_ESTIMATION");
        
        return feature == BATCH_TRANSACTIONS || 
               feature == TOKEN_VALIDATION || 
               feature == GAS_ESTIMATION;
    }
}
