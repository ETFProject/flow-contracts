// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/contracts/flow/FlowETFVault.sol";
import "../src/contracts/flow/FlowEIP7702ETFImplementation.sol";
import "../src/contracts/flow/FlowNativeAssets.sol";

contract TestFlowETF is Script {
    // Contract addresses (hardcoded from our deployment)
    address public assetFactory = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address public wflow = 0xa16E02E87b7454126E5E10d957A927A7F5B5d2be;
    address public trump = 0xB7A5bd0345EF1Cc5E66bf61BdeC17D2461fBd968;
    address public ankrFlow = 0xeEBe00Ac0756308ac4AaBfD76c05c4F3088B8883;
    address public usdc = 0x10C6E9530F1C1AF873a391030a1D9E8ed0630D26;
    address public weth = 0x603E1BD79259EbcbAaeD0c83eeC09cA0B89a5bcC;
    address public etfVault = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address public eip7702 = 0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // For Anvil, we need to fake Flow EVM Chain ID
        vm.chainId(545); // Set chainId to Flow EVM ID

        console.log("===========================================");
        console.log("Flow ETF Testing");
        console.log("===========================================");
        console.log("Tester:", deployer);
        console.log("ETF Vault:", etfVault);

        vm.startBroadcast(deployerPrivateKey);

        // Get contracts
        FlowETFVault vault = FlowETFVault(payable(etfVault));
        WrappedFlow wflowToken = WrappedFlow(payable(wflow));
        TrumpFlow trumpToken = TrumpFlow(trump);
        FlowUSDC usdcToken = FlowUSDC(usdc);

        // Test 1: Check TVL and NAV
        uint256 totalValue = vault.getTotalValue();
        uint256 nav = vault.getNetAssetValue();
        console.log("Test 1: Check ETF status");
        console.log("Total Value Locked:", totalValue / 1e18, "tokens");
        console.log("Net Asset Value:", nav / 1e18, "per share");

        // Test 2: Get all active assets
        address[] memory activeAssets = vault.getActiveAssets();
        console.log("Test 2: Active assets");
        console.log("Number of active assets:", activeAssets.length);
        
        // Test 3: Check if rebalancing is needed
        bool needsRebal = vault.needsRebalancing();
        console.log("Test 3: Rebalancing needed?", needsRebal);

        // Test 4: Deposit more WFLOW to ETF (create imbalance)
        console.log("Test 4: Deposit more WFLOW to create imbalance");
        console.log("WFLOW balance before:", wflowToken.balanceOf(deployer) / 1e18);
        wflowToken.approve(etfVault, 5000 * 1e18);
        vault.deposit(wflow, 5000 * 1e18);
        console.log("WFLOW balance after:", wflowToken.balanceOf(deployer) / 1e18);
        console.log("Rebalancing needed now?", vault.needsRebalancing());

        // Test 5: Rebalance an asset
        if (vault.needsRebalancing()) {
            console.log("Test 5: Rebalancing WFLOW");
            vault.rebalanceAsset(wflow);
            console.log("Rebalance complete");
            console.log("Rebalancing still needed?", vault.needsRebalancing());
        }

        // Test 6: Get allocation for an asset
        console.log("Test 6: Get WFLOW allocation");
        FlowETFVault.AssetAllocation memory wflowAlloc = vault.getAssetAllocation(wflow);
        console.log("WFLOW target weight:", wflowAlloc.targetWeight);
        console.log("WFLOW current weight:", wflowAlloc.currentWeight);
        console.log("WFLOW active:", wflowAlloc.isActive);

        // Test 7: Withdraw from ETF
        console.log("Test 7: Withdraw from ETF");
        uint256 etfBalance = vault.balanceOf(deployer);
        console.log("ETF Shares before:", etfBalance / 1e18);
        uint256 usdcBefore = usdcToken.balanceOf(deployer);
        console.log("USDC balance before:", usdcBefore / 1e6);
        
        // Withdraw 10% of ETF shares, receive TRUMP instead of USDC
        uint256 withdrawShares = etfBalance / 10;
        vault.withdraw(withdrawShares, trump, 0);
        
        console.log("ETF Shares after:", vault.balanceOf(deployer) / 1e18);
        console.log("TRUMP balance after:", trumpToken.balanceOf(deployer) / 1e18);

        // Test 8: Test fee collection
        console.log("Test 8: Collect fees");
        uint256 agentWalletBalance = vault.balanceOf(vault.agentWallet());
        console.log("Agent ETF balance before:", agentWalletBalance / 1e18);
        
        // Warp time forward to accumulate fees (1 month)
        vm.warp(block.timestamp + 30 days);
        
        vault.collectFees();
        
        agentWalletBalance = vault.balanceOf(vault.agentWallet());
        console.log("Agent ETF balance after:", agentWalletBalance / 1e18);
        
        // Test 9: EIP7702 integration - prepare batched operations
        console.log("Test 9: EIP7702 batched operations");
        
        // Create batch for deposit
        uint256[] memory operations = new uint256[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        bytes[] memory extraData = new bytes[](1);
        
        operations[0] = 0; // deposit
        tokens[0] = trump; // TRUMP token
        amounts[0] = 1000 * 1e18; // 1000 TRUMP
        
        (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) = 
            vault.createBatchedETFOperations(operations, tokens, amounts, extraData);
        
        console.log("Batch created for deposit of 1000 TRUMP");
        console.log("Number of operations:", targets.length);
        
        // We would typically execute these through the EIP7702 implementation
        // but for testing purposes we'll just call the target directly
        trumpToken.approve(etfVault, 1000 * 1e18);
        (bool success,) = targets[0].call(calldatas[0]);
        require(success, "Batch execution failed");
        
        console.log("Batch executed successfully");
        
        vm.stopBroadcast();
        
        console.log("===========================================");
        console.log("Testing complete!");
        console.log("Final TVL:", vault.getTotalValue() / 1e18);
        console.log("Final NAV:", vault.getNetAssetValue() / 1e18);
    }
} 