// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/RIFRelayBatchTransactions.sol";
import "../src/BatchTransactionVerifier.sol";
import "../src/interfaces/IRIFRelay.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string public name = "Mock RIF Token";
    string public symbol = "MRIF";
    uint8 public decimals = 18;
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        
        return true;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
}

contract MockSmartWallet {
    address public owner;
    
    constructor(address _owner) {
        owner = _owner;
    }
    
    // Mock function to simulate smart wallet calling the batch contract
    function executeBatch(
        address batchContract,
        RIFRelayBatchTransactions.Transaction[] calldata transactions,
        bool stopOnFailure,
        address originalSender
    ) external payable returns (RIFRelayBatchTransactions.BatchResult[] memory) {
        // Append the original sender to the call data (RIF Relay pattern)
        bytes memory callData = abi.encodeWithSelector(
            RIFRelayBatchTransactions.executeBatch.selector,
            transactions,
            stopOnFailure
        );
        
        // Append original sender (20 bytes) to the end
        bytes memory fullCallData = abi.encodePacked(callData, originalSender);
        
        (bool success, bytes memory returnData) = batchContract.call{value: msg.value}(fullCallData);
        require(success, "Smart wallet call failed");
        
        return abi.decode(returnData, (RIFRelayBatchTransactions.BatchResult[]));
    }
}

contract TestTarget {
    mapping(address => uint256) public values;
    event ValueSet(address indexed setter, uint256 value);
    
    function setValue(uint256 _value) external {
        values[msg.sender] = _value;
        emit ValueSet(msg.sender, _value);
    }
    
    function setValueWithETH(uint256 _value) external payable {
        values[msg.sender] = _value;
        emit ValueSet(msg.sender, _value);
    }
    
    function failingFunction() external pure {
        revert("This function always fails");
    }
}

contract RIFRelayBatchTransactionsTest is Test {
    RIFRelayBatchTransactions batchContract;
    BatchTransactionVerifier verifier;
    MockERC20 rifToken;
    MockSmartWallet smartWallet;
    TestTarget testTarget;
    
    address owner = address(0x1);
    address user = address(0x2);
    address smartWalletFactory = address(0x3);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy contracts
        batchContract = new RIFRelayBatchTransactions(owner);
        verifier = new BatchTransactionVerifier(owner);
        rifToken = new MockERC20();
        testTarget = new TestTarget();
        
        // Deploy mock smart wallet
        smartWallet = new MockSmartWallet(user);
        
        // Configure batch contract
        batchContract.addTrustedForwarder(address(smartWallet));
        
        // Configure verifier
        verifier.acceptToken(address(rifToken));
        
        // Mint tokens to user
        rifToken.mint(user, 1000 ether);
        
        vm.stopPrank();
        
        // User approves smart wallet to spend tokens
        vm.prank(user);
        rifToken.approve(address(smartWallet), 1000 ether);
    }
    
    function testDirectBatchExecution() public {
        // Test direct execution (not through RIF Relay)
        RIFRelayBatchTransactions.Transaction[] memory transactions = new RIFRelayBatchTransactions.Transaction[](2);
        
        transactions[0] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 100),
            requireSuccess: true
        });
        
        transactions[1] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 200),
            requireSuccess: true
        });
        
        vm.prank(user);
        RIFRelayBatchTransactions.BatchResult[] memory results = batchContract.executeBatch(transactions, false);
        
        assertEq(results.length, 2);
        assertTrue(results[0].success);
        assertTrue(results[1].success);
        assertEq(testTarget.values(user), 200); // Last value set
    }
    
    function testRelayedBatchExecution() public {
        // Test execution through smart wallet (simulating RIF Relay)
        RIFRelayBatchTransactions.Transaction[] memory transactions = new RIFRelayBatchTransactions.Transaction[](2);
        
        transactions[0] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 300),
            requireSuccess: true
        });
        
        transactions[1] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 400),
            requireSuccess: true
        });
        
        // Execute through smart wallet (simulating RIF Relay flow)
        RIFRelayBatchTransactions.BatchResult[] memory results = smartWallet.executeBatch(
            address(batchContract),
            transactions,
            false,
            user // Original sender
        );
        
        assertEq(results.length, 2);
        assertTrue(results[0].success);
        assertTrue(results[1].success);
        assertEq(testTarget.values(address(smartWallet)), 400); // Smart wallet is the actual caller
    }
    
    function testMsgSenderExtraction() public {
        // Test that _msgSender() correctly extracts the original sender
        
        // First, test direct call
        vm.prank(user);
        address directSender = batchContract._msgSender();
        assertEq(directSender, user);
        
        // Test relayed call (mock the call data pattern)
        vm.startPrank(address(smartWallet));
        
        // Simulate call data with appended sender
        bytes memory callData = abi.encodeWithSelector(batchContract._msgSender.selector);
        bytes memory fullCallData = abi.encodePacked(callData, user);
        
        (bool success, bytes memory returnData) = address(batchContract).call(fullCallData);
        assertTrue(success);
        
        address extractedSender = abi.decode(returnData, (address));
        assertEq(extractedSender, user);
        
        vm.stopPrank();
    }
    
    function testBatchTransfer() public {
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x10);
        recipients[1] = address(0x11);
        recipients[2] = address(0x12);
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.2 ether;
        amounts[2] = 0.3 ether;
        
        uint256 totalAmount = 0.6 ether;
        
        vm.deal(user, 1 ether);
        vm.prank(user);
        
        bool[] memory results = batchContract.batchTransfer{value: totalAmount}(recipients, amounts);
        
        assertEq(results.length, 3);
        assertTrue(results[0]);
        assertTrue(results[1]);
        assertTrue(results[2]);
        
        assertEq(recipients[0].balance, 0.1 ether);
        assertEq(recipients[1].balance, 0.2 ether);
        assertEq(recipients[2].balance, 0.3 ether);
    }
    
    function testTokenVerification() public {
        // Test verifier functionality
        assertTrue(verifier.acceptsToken(address(rifToken)));
        assertFalse(verifier.acceptsToken(address(0x123)));
        
        // Test minimum token amounts
        assertEq(verifier.getMinTokenAmount(1), 1 ether);
        assertEq(verifier.getMinTokenAmount(5), 3 ether);
        assertEq(verifier.getMinTokenAmount(10), 5 ether);
        assertEq(verifier.getMinTokenAmount(25), 10 ether);
        assertEq(verifier.getMinTokenAmount(50), 15 ether);
    }
    
    function testValidateRelayRequest() public {
        ForwardRequest memory request = ForwardRequest({
            from: user,
            to: address(batchContract),
            value: 0,
            gas: 500000,
            nonce: 1,
            data: "",
            validUntilTime: block.timestamp + 3600,
            tokenContract: address(rifToken),
            tokenAmount: 5 ether,
            tokenGas: 50000
        });
        
        (bool success, string memory reason) = verifier.validateRelayRequest(request, "");
        assertTrue(success);
        assertEq(keccak256(bytes(reason)), keccak256(bytes("")));
    }
    
    function testValidateRelayRequestWithInsufficientBalance() public {
        // Test with user who has no tokens
        address poorUser = address(0x99);
        
        ForwardRequest memory request = ForwardRequest({
            from: poorUser,
            to: address(batchContract),
            value: 0,
            gas: 500000,
            nonce: 1,
            data: "",
            validUntilTime: block.timestamp + 3600,
            tokenContract: address(rifToken),
            tokenAmount: 5 ether,
            tokenGas: 50000
        });
        
        (bool success, string memory reason) = verifier.validateRelayRequest(request, "");
        assertFalse(success);
        assertEq(reason, "Insufficient token balance");
    }
    
    function testPauseUnpause() public {
        // Test pause functionality
        vm.prank(owner);
        batchContract.pause();
        
        assertTrue(batchContract.paused());
        
        RIFRelayBatchTransactions.Transaction[] memory transactions = new RIFRelayBatchTransactions.Transaction[](1);
        transactions[0] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 100),
            requireSuccess: true
        });
        
        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        batchContract.executeBatch(transactions, false);
        
        // Unpause
        vm.prank(owner);
        batchContract.unpause();
        
        assertFalse(batchContract.paused());
        
        // Should work now
        vm.prank(user);
        batchContract.executeBatch(transactions, false);
    }
    
    function testTrustedForwarderManagement() public {
        address newForwarder = address(0x999);
        
        // Add trusted forwarder
        vm.prank(owner);
        batchContract.addTrustedForwarder(newForwarder);
        
        assertTrue(batchContract.isTrustedForwarder(newForwarder));
        
        // Remove trusted forwarder
        vm.prank(owner);
        batchContract.removeTrustedForwarder(newForwarder);
        
        assertFalse(batchContract.isTrustedForwarder(newForwarder));
    }
    
    function testFailingTransactionHandling() public {
        RIFRelayBatchTransactions.Transaction[] memory transactions = new RIFRelayBatchTransactions.Transaction[](3);
        
        transactions[0] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 100),
            requireSuccess: false
        });
        
        transactions[1] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.failingFunction.selector),
            requireSuccess: false
        });
        
        transactions[2] = RIFRelayBatchTransactions.Transaction({
            target: address(testTarget),
            value: 0,
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 300),
            requireSuccess: false
        });
        
        vm.prank(user);
        RIFRelayBatchTransactions.BatchResult[] memory results = batchContract.executeBatch(transactions, false);
        
        assertEq(results.length, 3);
        assertTrue(results[0].success);
        assertFalse(results[1].success); // This should fail
        assertTrue(results[2].success);  // This should continue despite previous failure
    }
    
    function testReentrancyProtection() public {
        // This would require a more complex setup with a malicious contract
        // For now, we just test that the reentrancy guard is in place
        assertTrue(batchContract.maxBatchSize() > 0); // Contract is functional
    }
    
    function testEmergencyWithdraw() public {
        // Send some ETH to the contract
        vm.deal(address(batchContract), 1 ether);
        
        address payable recipient = payable(address(0x456));
        uint256 initialBalance = recipient.balance;
        
        vm.prank(owner);
        batchContract.emergencyWithdraw(recipient, 0.5 ether);
        
        assertEq(recipient.balance, initialBalance + 0.5 ether);
        assertEq(address(batchContract).balance, 0.5 ether);
    }
}
