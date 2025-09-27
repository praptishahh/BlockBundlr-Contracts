// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/RIFRelayBatchTransactions.sol";
import "../src/BatchTransactionVerifier.sol";

/**
 * @title DeployRIFRelayBatch
 * @dev Deployment script for RIF Relay compatible batch transaction contracts
 */
contract DeployRIFRelayBatch is Script {
    
    // Configuration for different networks
    struct NetworkConfig {
        address rifTokenAddress;
        address smartWalletFactoryAddress;
        address relayHubAddress;
        address deployVerifierAddress;
        address relayVerifierAddress;
    }
    
    // Network configurations
    mapping(uint256 => NetworkConfig) public networkConfigs;
    
    function setUp() public {
        // Rootstock Testnet (Chain ID: 31)
        networkConfigs[31] = NetworkConfig({
            rifTokenAddress: 0x19F64674D8A5B4E652319F5e239eFd3bc969A1fE, // RIF Token on Testnet
            smartWalletFactoryAddress: 0xCBc3BC24da96Ef5606d3801E13E1DC6E98C5c877, // From RIF Relay docs
            relayHubAddress: 0xAd525463961399793f8716b0D85133ff7503a7C2, // From RIF Relay docs
            deployVerifierAddress: 0xc67f193Bb1D64F13FD49E2da6586a2F417e56b16, // From RIF Relay docs
            relayVerifierAddress: 0xB86c972Ff212838C4c396199B27a0DBe45560df8 // From RIF Relay docs
        });
        
        // Rootstock Mainnet (Chain ID: 30)
        networkConfigs[30] = NetworkConfig({
            rifTokenAddress: 0x2AcC95758f8b5F583470ba265EB685a8F45fC9D5, // RIF Token on Mainnet
            smartWalletFactoryAddress: 0x9EEbEC6C5157bEE13b451b1dfE1eE2cB40846323, // From RIF Relay docs
            relayHubAddress: 0x438Ce7f1FEC910588Be0fa0fAcD27D82De1DE0bC, // From RIF Relay docs
            deployVerifierAddress: 0x2FD633E358bc50Ccf6bf926D621E8612B55264C9, // From RIF Relay docs
            relayVerifierAddress: 0x5C9c7d96E6C59E55dA4dCf7F791AE58dAF8DBc86 // From RIF Relay docs
        });
        
        // Local Regtest (Chain ID: 33) - Placeholder addresses
        networkConfigs[33] = NetworkConfig({
            rifTokenAddress: address(0), // Will be deployed or set manually
            smartWalletFactoryAddress: address(0), // Will be set from RIF Relay deployment
            relayHubAddress: address(0), // Will be set from RIF Relay deployment
            deployVerifierAddress: address(0), // Will be set from RIF Relay deployment
            relayVerifierAddress: address(0) // Will be set from RIF Relay deployment
        });
    }
    
    function run() public {
        uint256 chainId = block.chainid;
        console.log("Deploying on chain ID:", chainId);
        
        NetworkConfig memory config = networkConfigs[chainId];
        
        // Verify we have network configuration
        if (chainId != 33 && config.smartWalletFactoryAddress == address(0)) {
            revert("Network configuration not found for chain ID");
        }
        
        vm.startBroadcast();
        
        // Deploy the verifier first
        BatchTransactionVerifier verifier = new BatchTransactionVerifier(msg.sender);
        console.log("BatchTransactionVerifier deployed at:", address(verifier));
        
        // Deploy the main batch transaction contract
        RIFRelayBatchTransactions batchContract = new RIFRelayBatchTransactions(msg.sender);
        console.log("RIFRelayBatchTransactions deployed at:", address(batchContract));
        
        // Configure the contracts if we have network config
        if (config.smartWalletFactoryAddress != address(0)) {
            // Add the smart wallet factory as a trusted forwarder
            batchContract.addTrustedForwarder(config.smartWalletFactoryAddress);
            console.log("Added Smart Wallet Factory as trusted forwarder");
            
            // Accept RIF token in the verifier
            if (config.rifTokenAddress != address(0)) {
                verifier.acceptToken(config.rifTokenAddress);
                console.log("RIF Token accepted in verifier");
            }
        }
        
        vm.stopBroadcast();
        
        // Print deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", chainId);
        console.log("BatchTransactionVerifier:", address(verifier));
        console.log("RIFRelayBatchTransactions:", address(batchContract));
        console.log("Owner:", msg.sender);
        
        if (config.rifTokenAddress != address(0)) {
            console.log("RIF Token:", config.rifTokenAddress);
        }
        if (config.smartWalletFactoryAddress != address(0)) {
            console.log("Smart Wallet Factory:", config.smartWalletFactoryAddress);
        }
        
        console.log("\n=== Next Steps ===");
        console.log("1. If on regtest, deploy RIF Relay contracts first");
        console.log("2. Add RIF Relay Smart Wallet Factory as trusted forwarder:");
        console.log("   batchContract.addTrustedForwarder(<SMART_WALLET_FACTORY>)");
        console.log("3. Accept tokens in the verifier:");
        console.log("   verifier.acceptToken(<TOKEN_ADDRESS>)");
        console.log("4. Configure minimum token amounts if needed");
        console.log("5. Register the verifier with RIF Relay Hub if required");
    }
    
    /**
     * @dev Deploy only the batch transaction contract (if verifier already exists)
     */
    function deployBatchOnly() public {
        vm.startBroadcast();
        
        RIFRelayBatchTransactions batchContract = new RIFRelayBatchTransactions(msg.sender);
        console.log("RIFRelayBatchTransactions deployed at:", address(batchContract));
        
        vm.stopBroadcast();
    }
    
    /**
     * @dev Deploy only the verifier contract
     */
    function deployVerifierOnly() public {
        vm.startBroadcast();
        
        BatchTransactionVerifier verifier = new BatchTransactionVerifier(msg.sender);
        console.log("BatchTransactionVerifier deployed at:", address(verifier));
        
        vm.stopBroadcast();
    }
    
    /**
     * @dev Configure existing contracts with RIF Relay addresses
     */
    function configureContracts(
        address batchContractAddress,
        address verifierAddress,
        address smartWalletFactory,
        address rifToken
    ) public {
        require(batchContractAddress != address(0), "Invalid batch contract address");
        require(verifierAddress != address(0), "Invalid verifier address");
        
        vm.startBroadcast();
        
        RIFRelayBatchTransactions batchContract = RIFRelayBatchTransactions(payable(batchContractAddress));
        BatchTransactionVerifier verifier = BatchTransactionVerifier(verifierAddress);
        
        if (smartWalletFactory != address(0)) {
            batchContract.addTrustedForwarder(smartWalletFactory);
            console.log("Added Smart Wallet Factory as trusted forwarder");
        }
        
        if (rifToken != address(0)) {
            verifier.acceptToken(rifToken);
            console.log("RIF Token accepted in verifier");
        }
        
        vm.stopBroadcast();
        
        console.log("Configuration completed");
    }
}
