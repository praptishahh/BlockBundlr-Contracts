// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract TestTarget {
    uint256 public counter;

    event Incremented(address sender, uint256 newValue);

    function increment() external {
        counter += 1;
        emit Incremented(msg.sender, counter);
    }

    function setValue(uint256 val) external {
        counter = val;
        emit Incremented(msg.sender, counter);
    }
}
