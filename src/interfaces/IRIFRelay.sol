// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IRIFRelay
 * @dev Interface for RIF Relay integration with batch transactions
 */

// Forward Request structure for RIF Relay
struct ForwardRequest {
    address from;        // Smart wallet owner
    address to;          // Target contract
    uint256 value;       // Native currency value
    uint256 gas;         // Gas limit
    uint256 nonce;       // Nonce from smart wallet
    bytes data;          // Call data
    uint256 validUntilTime; // Transaction expiration
    address tokenContract;   // Token used for payment
    uint256 tokenAmount;     // Amount of tokens to pay
    uint256 tokenGas;        // Gas for token transfer
}

// Relay Data structure
struct RelayData {
    uint256 gasPrice;
    address callVerifier;
    address callForwarder;  // Smart wallet address
    address feesReceiver;   // Worker or collector address
}

/**
 * @title IRelayRecipient
 * @dev Interface for contracts that can receive relayed calls
 */
interface IRelayRecipient {
    /**
     * @dev Returns the trusted forwarder for this contract
     */
    function isTrustedForwarder(address forwarder) external view returns (bool);
    
    /**
     * @dev Returns the original sender of a relayed call
     */
    function _msgSender() external view returns (address);
    
    /**
     * @dev Returns the original msg.data of a relayed call
     */
    function _msgData() external view returns (bytes calldata);
}

/**
 * @title ISmartWallet
 * @dev Interface for RIF Relay Smart Wallets
 */
interface ISmartWallet {
    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 txGas
    ) external returns (bool success, bytes memory returnData);
    
    function executeBatch(
        address[] calldata to,
        uint256[] calldata value,
        bytes[] calldata data,
        uint256[] calldata txGas
    ) external returns (bool[] memory success, bytes[] memory returnData);
    
    function nonce() external view returns (uint256);
    function owner() external view returns (address);
}

/**
 * @title IRelayVerifier
 * @dev Interface for RIF Relay verifiers
 */
interface IRelayVerifier {
    function acceptsToken(address token) external view returns (bool);
    
    function versionVerifier() external view returns (string memory);
}

/**
 * @title IERC20
 * @dev Interface for ERC20 tokens used in relay payments
 */
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}
