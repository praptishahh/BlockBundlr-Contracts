// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/BatchTransactions.sol";

/**
 * @title DeployBatchTransactions
 * @dev Script to deploy BatchTransactions contract on Rootstock
 */
contract DeployBatchTransactionsSimple is Script {
    
    function run() external {
        // When using --private-key flag, we don't need to read from env
        // vm.startBroadcast() will automatically use the provided private key
        
        console.log("Deploying BatchTransactions contract...");
        console.log("Deployer will be determined by the private key used");
        
        vm.startBroadcast();
        
        BatchTransactions batchContract = new BatchTransactions();
        
        vm.stopBroadcast();
        
        console.log("BatchTransactions deployed at:", address(batchContract));
        console.log("Contract is now ownerless and immutable");
        console.log("All addresses can execute batch transactions");
        console.log("Max batch size:", batchContract.maxBatchSize());
        console.log("Max gas per transaction:", batchContract.maxGasPerTransaction());
        
        // Verify deployment
        require(address(batchContract) != address(0), "Deployment failed");
        
        console.log("Deployment successful!");
        
        // Log important information for verification
        console.log("\n=== Deployment Summary ===");
        console.log("Contract Address:", address(batchContract));
        console.log("Network: Rootstock");
        console.log("Contract Type: Ownerless/Immutable");
        console.log("Access: Public (Any address can execute)");
        console.log("========================\n");
    }
}