// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/BatchTransactions.sol";
import "../src/TestTarget.sol";

contract TestBatchScript is Script {
    function run() external {
        // Use string addresses with correct checksum casing and parse them
        address payable batchAddress = payable(vm.parseAddress("0xa46A6e492A3A5a7BCFad668e5Ed7fe304c0c00Df"));
        address payable testTargetAddress = payable(vm.parseAddress("0x3f15c5C404A21439C6f8cC75BC3652c03833B277"));

        BatchTransactions batch = BatchTransactions(batchAddress);
        TestTarget target = TestTarget(testTargetAddress);

        BatchTransactions.Transaction[] memory txns = new BatchTransactions.Transaction[](2);

        txns[0] = BatchTransactions.Transaction({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(target.increment.selector),
            requireSuccess: true
        });

        txns[1] = BatchTransactions.Transaction({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(target.setValue.selector, 10),
            requireSuccess: true
        });

        vm.startBroadcast();
        batch.executeBatch(txns, false);
        vm.stopBroadcast();
    }
}
