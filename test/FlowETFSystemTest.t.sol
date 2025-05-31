// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/FlowETFVault.sol";
import "../src/FlowEIP7702Implementation.sol";
import "../src/FlowTestAssets.sol";

contract FlowETFSystemTest is Test {
    
    // Contracts
    FlowETFVault public etfVault;
    FlowEIP7702Implementation public eip7702;
    AssetFactory public assetFactory;
    
    // Test assets
    WrappedFlow public wflow;
    FlowUSDC public usdc;
    FlowWETH public weth;
    AnkrFlow public ankrFlow;
    TrumpFlow public trump;
    
    // Test accounts
    address public owner = makeAddr("owner");
    address public agentWallet = makeAddr("agentWallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    // Events for testing
    event AssetAdded(address indexed token, uint256 targetWeight);
    event AgentWalletSet(address indexed oldAgent, address indexed newAgent);
    
    function setUp() public {
        // Set chain ID to Flow EVM
        vm.chainId(545);
        
        // Fund accounts with FLOW
        vm.deal(owner, 1000 ether);
        vm.deal(agentWallet, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        // Deploy contracts
        vm.startPrank(owner);
        
        // Deploy asset factory and assets
        assetFactory = new AssetFactory(owner);
        assetFactory.deployAssets();
        
        (
            address _wflow,
            address _usdc,
            address _weth,
            address _ankrFlow,
            address _trump
        ) = assetFactory.getAssets();
        
        wflow = WrappedFlow(payable(_wflow));
        usdc = FlowUSDC(_usdc);
        weth = FlowWETH(_weth);
        ankrFlow = AnkrFlow(payable(_ankrFlow));
        trump = TrumpFlow(_trump);
        
        // Deploy EIP-7702 implementation
        eip7702 = new FlowEIP7702Implementation();
        
        // Deploy ETF vault
        etfVault = new FlowETFVault(
            "Flow Test ETF",
            "FETF",
            agentWallet,
            owner
        );
        
        vm.stopPrank();
    }
    
    function testInitialSetup() public {
        // Test initial state
        assertEq(etfVault.agentWallet(), agentWallet);
        assertEq(etfVault.owner(), owner);
        assertTrue(etfVault.authorizedAgents(agentWallet));
        assertEq(etfVault.getTotalValue(), 0);
        assertEq(etfVault.totalSupply(), 0);
    }
    
    function testAddAssets() public {
        vm.startPrank(agentWallet);
        
        // Test adding assets
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(wflow), 4000);
        etfVault.addAsset(address(wflow), 4000); // 40%
        
        etfVault.addAsset(address(usdc), 3000); // 30%
        etfVault.addAsset(address(weth), 2000); // 20%
        etfVault.addAsset(address(ankrFlow), 1000); // 10%
        
        // Verify total target weight
        assertEq(etfVault.getTotalTargetWeight(), 10000); // 100%
        
        // Test adding asset that would exceed 100%
        vm.expectRevert(FlowETFVault.InvalidWeight.selector);
        etfVault.addAsset(address(trump), 100);
        
        vm.stopPrank();
    }
    
    function testAssetManagement() public {
        _setupAssets();
        
        vm.startPrank(agentWallet);
        
        // Test asset removal
        etfVault.removeAsset(address(ankrFlow));
        assertFalse(etfVault.supportedTokens(address(ankrFlow)));
        
        // Test adding asset back
        etfVault.addAsset(address(trump), 1000);
        assertTrue(etfVault.supportedTokens(address(trump)));
        
        vm.stopPrank();
    }
    
    function testETFDeposit() public {
        _setupAssets();
        _fundUsersWithTokens();
        
        vm.startPrank(user1);
        
        // Test deposit
        uint256 depositAmount = 1000 * 1e18;
        wflow.approve(address(etfVault), depositAmount);
        
        uint256 sharesBefore = etfVault.balanceOf(user1);
        etfVault.deposit(address(wflow), depositAmount);
        uint256 sharesAfter = etfVault.balanceOf(user1);
        
        assertTrue(sharesAfter > sharesBefore);
        assertEq(etfVault.getTotalValue(), depositAmount);
        
        vm.stopPrank();
    }
    
    function testETFWithdraw() public {
        _setupAssets();
        _fundUsersWithTokens();
        
        vm.startPrank(user1);
        
        // First deposit
        uint256 depositAmount = 1000 * 1e18;
        wflow.approve(address(etfVault), depositAmount);
        etfVault.deposit(address(wflow), depositAmount);
        
        // Then withdraw same token that was deposited
        uint256 shares = etfVault.balanceOf(user1);
        uint256 wflowBefore = wflow.balanceOf(user1);
        
        etfVault.withdraw(shares / 2, address(wflow), 0);
        
        uint256 wflowAfter = wflow.balanceOf(user1);
        assertTrue(wflowAfter > wflowBefore);
        assertTrue(etfVault.balanceOf(user1) < shares);
        
        vm.stopPrank();
    }
    
    function testEIP7702Initialization() public {
        _setupAssets();
        
        // Test initialization
        vm.prank(user1);
        eip7702.initialize(address(etfVault), agentWallet);
        
        assertEq(eip7702.getVault(), address(etfVault));
        assertEq(eip7702.getAgent(), agentWallet);
        assertEq(eip7702.getNonce(), 1);
    }
    function testETFWeightRedistribution() public {
      uint256 newWeight1 = 6000;
      uint256 newWeight2 = 1000;
      uint256 assetIndex1 = etfVault.assetIndex(address(wflow));
      uint256 assetIndex2 = etfVault.assetIndex(address(usdc));
      _setupAssets();
      eip7702.initialize(address(etfVault), agentWallet);
      vm.prank(agentWallet);
      address[] memory newTokens = new address[] (2);
      newTokens[0] = address(wflow);
      newTokens[1] = address(usdc);

      uint256[] memory newWeights = new uint256[] (2);
      newWeights[0] = newWeight1;
      newWeights[1] = newWeight2;
      etfVault.updateAllAssetWeights(newTokens,newWeights);
      (,uint256 targetWeight1,,) = etfVault.assets(assetIndex1);
      (,uint256 targetWeight2,,)= etfVault.assets(assetIndex2);
      assertEq(newWeight1, targetWeight1);
    }
    
    function testEIP7702BatchExecution() public {
        _setupAssets();
        _fundUsersWithTokens();
        
        // Initialize EIP-7702
        vm.prank(user1);
        eip7702.initialize(address(etfVault), agentWallet);
        
        // Prepare batch calls
        address[] memory targets = new address[](2);
        bytes[] memory calldatas = new bytes[](2);
        uint256[] memory values = new uint256[](2);
        
        // Call 1: Approve WFLOW
        targets[0] = address(wflow);
        calldatas[0] = abi.encodeWithSignature("approve(address,uint256)", address(etfVault), 1000 * 1e18);
        values[0] = 0;
        
        // Call 2: Deposit to ETF
        targets[1] = address(etfVault);
        calldatas[1] = abi.encodeWithSignature("deposit(address,uint256)", address(wflow), 1000 * 1e18);
        values[1] = 0;
        
        // Fund the EIP-7702 contract (simulating delegated EOA)
        vm.prank(owner);
        wflow.transfer(address(eip7702), 2000 * 1e18);
        
        // Execute batch as agent
        vm.prank(agentWallet);
        uint256 successCount = eip7702.executeBatch(targets, calldatas, values);
        
        assertEq(successCount, 2);
        assertEq(eip7702.getNonce(), 2);
    }
    
    function testEIP7702ETFOperations() public {
        _setupAssets();
        _fundUsersWithTokens();
        
        // Initialize EIP-7702
        vm.prank(user1);
        eip7702.initialize(address(etfVault), agentWallet);
        
        // Fund the EIP-7702 contract (simulating delegated EOA)
        vm.prank(owner);
        wflow.transfer(address(eip7702), 5000 * 1e18);
        
        vm.startPrank(agentWallet);
        
        // Test deposit through EIP-7702
        eip7702.depositToETF(address(wflow), 1000 * 1e18);
        assertTrue(etfVault.balanceOf(address(eip7702)) > 0);
        
        // Test withdrawal through EIP-7702
        uint256 shares = etfVault.balanceOf(address(eip7702));
        eip7702.withdrawFromETF(shares / 2, address(wflow), 0);
        assertTrue(wflow.balanceOf(address(eip7702)) > 0);
        
        vm.stopPrank();
    }
    
    function testLiquidityManagement() public {
        _setupAssets();
        _fundVaultWithTokens();
        
        // Create a mock protocol (just an address for testing)
        address mockProtocol = makeAddr("mockProtocol");
        vm.deal(mockProtocol, 100 ether);
        
        vm.startPrank(agentWallet);
        
        // Test moving funds to protocol
        uint256 moveAmount = 100 * 1e18;
        bytes memory mockData = abi.encodeWithSignature("deposit(uint256)", moveAmount);
        
        FlowETFVault.Asset memory assetBefore = etfVault.getAsset(address(wflow));
        
        etfVault.moveFundsToProtocol(mockProtocol, address(wflow), moveAmount, mockData);
        
        FlowETFVault.Asset memory assetAfter = etfVault.getAsset(address(wflow));
        assertEq(assetAfter.balance, assetBefore.balance - moveAmount);
        
        vm.stopPrank();
    }
    
    function testCrossChainSupport() public {
        _setupAssets();
        
        vm.startPrank(agentWallet);
        
        // Add cross-chain vault
        uint256 targetChainId = 84532; // Base Sepolia
        address targetVault = makeAddr("baseVault");
        
        etfVault.addChainVault(targetChainId, targetVault);
        assertTrue(etfVault.supportedChains(targetChainId));
        assertEq(etfVault.chainVaults(targetChainId), targetVault);
        
        vm.stopPrank();
    }
    
    function testAccessControl() public {
        _setupAssets();
        
        // Test unauthorized access
        vm.prank(user1);
        vm.expectRevert(FlowETFVault.Unauthorized.selector);
        etfVault.addAsset(address(trump), 1000);
        
        // Test owner functions
        vm.prank(owner);
        etfVault.setAgentAuthorization(user2, true);
        assertTrue(etfVault.authorizedAgents(user2));
        
        // Remove one asset first to make room (total weight is 100%)
        vm.prank(user2);
        etfVault.removeAsset(address(ankrFlow)); // Remove 1000 weight
        
        // Test authorized agent can now call functions
        vm.prank(user2);
        etfVault.addAsset(address(trump), 500); // Should not revert now
    }
    
    function testEmergencyFunctions() public {
        _setupAssets();
        _fundVaultWithTokens();
        
        vm.startPrank(owner);
        
        // Test emergency pause
        etfVault.emergencyPause();
        assertTrue(etfVault.paused());
        
        // Test operations fail when paused
        vm.stopPrank();
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        etfVault.deposit(address(wflow), 1000 * 1e18);
        
        // Test unpause
        vm.prank(owner);
        etfVault.emergencyUnpause();
        assertFalse(etfVault.paused());
        
        vm.stopPrank();
    }
    
    function testInvalidOperations() public {
        // Test invalid asset addition
        vm.prank(agentWallet);
        vm.expectRevert(FlowETFVault.InvalidAsset.selector);
        etfVault.addAsset(address(0), 1000);
        
        // Test invalid weight
        vm.prank(agentWallet);
        vm.expectRevert(FlowETFVault.InvalidWeight.selector);
        etfVault.addAsset(address(wflow), 0);
        
        // Test deposit of unsupported asset
        vm.prank(user1);
        vm.expectRevert(FlowETFVault.AssetNotSupported.selector);
        etfVault.deposit(address(trump), 1000 * 1e18);
    }
    
    // Helper functions
    function _setupAssets() internal {
        vm.startPrank(agentWallet);
        etfVault.addAsset(address(wflow), 4000); // 40%
        etfVault.addAsset(address(usdc), 3000); // 30%
        etfVault.addAsset(address(weth), 2000); // 20%
        etfVault.addAsset(address(ankrFlow), 1000); // 10%
        vm.stopPrank();
    }
    
    function _fundUsersWithTokens() internal {
        vm.startPrank(owner);
        
        // Fund users with test tokens
        wflow.transfer(user1, 10000 * 1e18);
        wflow.transfer(user2, 10000 * 1e18);
        
        usdc.transfer(user1, 50000 * 1e6);
        usdc.transfer(user2, 50000 * 1e6);
        
        weth.transfer(user1, 100 * 1e18);
        weth.transfer(user2, 100 * 1e18);
        
        ankrFlow.transfer(user1, 5000 * 1e18);
        ankrFlow.transfer(user2, 5000 * 1e18);
        
        vm.stopPrank();
    }
    
    function _fundVaultWithTokens() internal {
        vm.startPrank(owner);
        
        // Fund vault with initial liquidity
        wflow.transfer(address(etfVault), 10000 * 1e18);
        usdc.transfer(address(etfVault), 50000 * 1e6);
        weth.transfer(address(etfVault), 100 * 1e18);
        ankrFlow.transfer(address(etfVault), 2500 * 1e18);
        
        vm.stopPrank();
        
        // Update asset balances
        vm.startPrank(agentWallet);
        etfVault.updateAssetBalance(address(wflow));
        etfVault.updateAssetBalance(address(usdc));
        etfVault.updateAssetBalance(address(weth));
        etfVault.updateAssetBalance(address(ankrFlow));
        vm.stopPrank();
    }
}
