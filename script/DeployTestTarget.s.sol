// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/TestTarget.sol";

contract DeployTestTarget is Script {
    function run() external {
        vm.startBroadcast();

        TestTarget testTarget = new TestTarget();

        vm.stopBroadcast();

        console.log("TestTarget deployed at:", address(testTarget));
    }
}
