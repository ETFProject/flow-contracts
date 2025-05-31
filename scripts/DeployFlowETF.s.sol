// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/contracts/flow/FlowETFVault.sol";
import "../src/contracts/flow/FlowEIP7702ETFImplementation.sol";
import "../src/contracts/flow/FlowNativeAssets.sol";

contract DeployFlowETF is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Ensure we're on a testnet or anvil
        require(block.chainid != 1, "Don't deploy on mainnet");

        // For Anvil, we need to fake Flow EVM Chain ID
        vm.chainId(545); // Set chainId to Flow EVM ID

        console.log("===========================================");
        console.log("Flow ETF Vault Deployment");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Flow Asset Factory
        FlowAssetFactory assetFactory = new FlowAssetFactory(deployer);
        console.log("FlowAssetFactory deployed:", address(assetFactory));

        // Deploy all assets (WFLOW, TRUMP, ankrFLOW, USDC, WETH)
        assetFactory.deployAllAssets();
        console.log("All Flow assets deployed");

        // Get asset addresses
        (
            address wflow,
            address trump,
            address ankrFlow,
            address usdc,
            address weth
        ) = assetFactory.getAllAssets();

        console.log("WFLOW:", wflow);
        console.log("TRUMP:", trump);
        console.log("ankrFLOW:", ankrFlow);
        console.log("USDC:", usdc);
        console.log("WETH:", weth);

        // We already have liquidity from the constructor mints
        console.log("Initial assets already have liquidity from constructors");
        
        // Deploy Flow ETF Vault
        FlowETFVault etfVault = new FlowETFVault(
            "Flow ETF Vault",
            "FETF",
            deployer,  // Agent wallet
            deployer   // Initial owner
        );
        console.log("FlowETFVault deployed:", address(etfVault));

        // Add assets to ETF Vault with allocation percentages
        etfVault.addAsset(wflow, 4000);    // 40% WFLOW
        etfVault.addAsset(trump, 2000);    // 20% TRUMP
        etfVault.addAsset(ankrFlow, 4000); // 40% ankrFLOW (adjusted to total 100%)
        console.log("Assets added to ETF Vault");

        // Approve and deposit tokens to ETF
        WrappedFlow(payable(wflow)).approve(address(etfVault), 10000 * 1e18);
        TrumpFlow(trump).approve(address(etfVault), 50000 * 1e18);
        AnkrFlow(payable(ankrFlow)).approve(address(etfVault), 5000 * 1e18);

        // Deposit tokens to ETF - just use the 3 main assets
        etfVault.deposit(wflow, 10000 * 1e18);
        etfVault.deposit(trump, 50000 * 1e18);
        etfVault.deposit(ankrFlow, 5000 * 1e18);
        console.log("Initial liquidity added to ETF");

        // Deploy EIP7702 Implementation
        FlowEIP7702ETFImplementation eip7702 = new FlowEIP7702ETFImplementation();
        console.log("FlowEIP7702ETFImplementation deployed:", address(eip7702));

        // First authorize the EIP7702 implementation contract as an agent
        etfVault.setAgentAuthorization(address(eip7702), true);
        console.log("EIP7702 implementation authorized as agent");

        // Initialize the EIP7702 implementation
        (bool success,) = address(eip7702).call(
            abi.encodeWithSignature("initializeFlowETF(address,address)", address(etfVault), deployer)
        );
        require(success, "EIP7702 initialization failed");
        console.log("EIP7702 implementation initialized");

        // Send ETH to the vault for gas
        payable(address(etfVault)).transfer(0.1 ether);
        console.log("ETH sent to vault for gas: 0.1 ETH");

        vm.stopBroadcast();

        console.log("Deployment complete!");
        console.log("===========================================");
        console.log("FlowAssetFactory:", address(assetFactory));
        console.log("WFLOW:", wflow);
        console.log("TRUMP:", trump);
        console.log("ankrFLOW:", ankrFlow);
        console.log("USDC:", usdc);
        console.log("WETH:", weth);
        console.log("FlowETFVault:", address(etfVault));
        console.log("FlowEIP7702ETFImplementation:", address(eip7702));

        // Write deployment info to file
        string memory deploymentInfo = vm.serializeAddress("deployment", "assetFactory", address(assetFactory));
        deploymentInfo = vm.serializeAddress("deployment", "wflow", wflow);
        deploymentInfo = vm.serializeAddress("deployment", "trump", trump);
        deploymentInfo = vm.serializeAddress("deployment", "ankrFlow", ankrFlow);
        deploymentInfo = vm.serializeAddress("deployment", "usdc", usdc);
        deploymentInfo = vm.serializeAddress("deployment", "weth", weth);
        deploymentInfo = vm.serializeAddress("deployment", "etfVault", address(etfVault));
        deploymentInfo = vm.serializeAddress("deployment", "eip7702", address(eip7702));
        deploymentInfo = vm.serializeUint("deployment", "timestamp", block.timestamp);
        deploymentInfo = vm.serializeUint("deployment", "chainId", block.chainid);
        
        try vm.writeJson(deploymentInfo, "./deployment-flow-etf.json") {
            console.log("Deployment info written to deployment-flow-etf.json");
        } catch {
            console.log("Could not write deployment info to file");
        }
    }
} 