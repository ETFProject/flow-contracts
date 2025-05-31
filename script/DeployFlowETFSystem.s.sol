// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/FlowETFVault.sol";
import "../src/FlowEIP7702Implementation.sol";
import "../src/FlowTestAssets.sol";

/**
 * @title DeployFlowETFSystem
 * @notice Clean deployment script for Flow ETF system
 * @dev Deploys on Flow EVM testnet (Chain ID: 545)
 */
contract DeployFlowETFSystem is Script {
    
    // Flow EVM Testnet configuration
    uint256 public constant FLOW_TESTNET_CHAIN_ID = 545;
    string public constant FLOW_TESTNET_RPC = "https://testnet.evm.nodes.onflow.org";
    
    // Deployment state
    struct Deployment {
        address etfVault;
        address eip7702Implementation;
        address assetFactory;
        address wflow;
        address usdc;
        address weth;
        address ankrFlow;
        address trump;
        address agentWallet;
        address deployer;
    }
    
    function run() external {
        // Get private key and agent wallet from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address agentWallet = vm.envOr("AGENT_WALLET", deployer);
        
        console.log("===========================================");
        console.log("Flow ETF System Deployment");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Agent Wallet:", agentWallet);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance / 1e18, "FLOW");
        
        // Verify we're on Flow EVM
        require(block.chainid == FLOW_TESTNET_CHAIN_ID, "Must deploy on Flow EVM Testnet");
        require(deployer.balance > 0.1 ether, "Insufficient balance for deployment");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Asset Factory and assets
        console.log("\n1. Deploying Asset Factory...");
        AssetFactory assetFactory = new AssetFactory(deployer);
        console.log("   Asset Factory:", address(assetFactory));
        
        console.log("\n2. Deploying Test Assets...");
        assetFactory.deployAssets();
        
        (
            address wflow,
            address usdc,
            address weth,
            address ankrFlow,
            address trump
        ) = assetFactory.getAssets();
        
        console.log("   WFLOW:", wflow);
        console.log("   USDC:", usdc);
        console.log("   WETH:", weth);
        console.log("   ankrFLOW:", ankrFlow);
        console.log("   TRUMP:", trump);
        
        // 2. Deploy EIP-7702 Implementation
        console.log("\n3. Deploying EIP-7702 Implementation...");
        FlowEIP7702Implementation eip7702 = new FlowEIP7702Implementation();
        console.log("   EIP-7702 Implementation:", address(eip7702));
        
        // 3. Deploy ETF Vault
        console.log("\n4. Deploying ETF Vault...");
        FlowETFVault etfVault = new FlowETFVault(
            "Flow Multi-Asset ETF",
            "FMAF",
            agentWallet,
            deployer
        );
        console.log("   ETF Vault:", address(etfVault));
        
        // 4. Configure ETF with assets
        console.log("\n5. Adding Assets to ETF...");
        
        // Add WFLOW (40% allocation)
        etfVault.addAsset(wflow, 4000);
        console.log("   Added WFLOW with 40% target weight");
        
        // Add USDC (30% allocation)
        etfVault.addAsset(usdc, 3000);
        console.log("   Added USDC with 30% target weight");
        
        // Add WETH (20% allocation)
        etfVault.addAsset(weth, 2000);
        console.log("   Added WETH with 20% target weight");
        
        // Add ankrFLOW (10% allocation)
        etfVault.addAsset(ankrFlow, 1000);
        console.log("   Added ankrFLOW with 10% target weight");
        
        // 5. Fund ETF with initial liquidity
        console.log("\n6. Adding Initial Liquidity...");
        
        // Transfer tokens to ETF vault for initial liquidity
        WrappedFlow(payable(wflow)).transfer(address(etfVault), 10000 * 1e18);
        FlowUSDC(usdc).transfer(address(etfVault), 50000 * 1e6);
        FlowWETH(weth).transfer(address(etfVault), 100 * 1e18);
        AnkrFlow(payable(ankrFlow)).transfer(address(etfVault), 2500 * 1e18);
        
        // Update asset balances in vault
        etfVault.updateAssetBalance(wflow);
        etfVault.updateAssetBalance(usdc);
        etfVault.updateAssetBalance(weth);
        etfVault.updateAssetBalance(ankrFlow);
        
        console.log("   Initial liquidity added and balances updated");
        
        // 6. Fund agent wallet with test tokens
        console.log("\n7. Funding Agent Wallet...");
        assetFactory.fundUser(agentWallet);
        console.log("   Agent wallet funded with test tokens");
        
        vm.stopBroadcast();
        
        // 7. Save deployment info
        Deployment memory deployment = Deployment({
            etfVault: address(etfVault),
            eip7702Implementation: address(eip7702),
            assetFactory: address(assetFactory),
            wflow: wflow,
            usdc: usdc,
            weth: weth,
            ankrFlow: ankrFlow,
            trump: trump,
            agentWallet: agentWallet,
            deployer: deployer
        });
        
        _saveDeploymentInfo(deployment);
        _printSummary(deployment);
        _generateTestingInstructions(deployment);
    }
    
    function _saveDeploymentInfo(Deployment memory deployment) internal {
        string memory json = string.concat(
            '{\n',
            '  "network": "flow-evm-testnet",\n',
            '  "chainId": 545,\n',
            '  "rpcUrl": "', FLOW_TESTNET_RPC, '",\n',
            '  "explorer": "https://evm-testnet.flowscan.io",\n',
            '  "contracts": {\n',
            '    "etfVault": "', vm.toString(deployment.etfVault), '",\n',
            '    "eip7702Implementation": "', vm.toString(deployment.eip7702Implementation), '",\n',
            '    "assetFactory": "', vm.toString(deployment.assetFactory), '"\n',
            '  },\n',
            '  "assets": {\n',
            '    "WFLOW": "', vm.toString(deployment.wflow), '",\n',
            '    "USDC": "', vm.toString(deployment.usdc), '",\n',
            '    "WETH": "', vm.toString(deployment.weth), '",\n',
            '    "ankrFLOW": "', vm.toString(deployment.ankrFlow), '",\n',
            '    "TRUMP": "', vm.toString(deployment.trump), '"\n',
            '  },\n',
            '  "agentWallet": "', vm.toString(deployment.agentWallet), '",\n',
            '  "deployer": "', vm.toString(deployment.deployer), '"\n',
            '}'
        );
        
        vm.writeFile("deployment-flow-etf.json", json);
        console.log("\n Deployment info saved to: deployment-flow-etf.json");
    }
    
    function _printSummary(Deployment memory deployment) internal view {
        console.log("\n===========================================");
        console.log("Deployment Summary");
        console.log("===========================================");
        
        console.log("\nCore Contracts:");
        console.log("  ETF Vault:", deployment.etfVault);
        console.log("  EIP-7702 Implementation:", deployment.eip7702Implementation);
        console.log("  Asset Factory:", deployment.assetFactory);
        
        console.log("\nTest Assets:");
        console.log("  WFLOW:", deployment.wflow);
        console.log("  USDC:", deployment.usdc);
        console.log("  WETH:", deployment.weth);
        console.log("  ankrFLOW:", deployment.ankrFlow);
        console.log("  TRUMP:", deployment.trump);
        
        console.log("\nConfiguration:");
        console.log("  Agent Wallet:", deployment.agentWallet);
        console.log("  Deployer:", deployment.deployer);
        console.log("  Network: Flow EVM Testnet");
        console.log("  Chain ID: 545");
    }
    
    function _generateTestingInstructions(Deployment memory deployment) internal view {
        console.log("\n===========================================");
        console.log("Testing Instructions");
        console.log("===========================================");
        
        console.log("\n1. Get test tokens:");
        console.log("  WFLOW:", deployment.wflow);
        console.log("  USDC:", deployment.usdc);
        console.log("  WETH:", deployment.weth);
        
        console.log("\n2. ETF Vault:", deployment.etfVault);
        console.log("\n3. EIP-7702 Implementation:", deployment.eip7702Implementation);
        
        console.log("\n4. Monitor URLs:");
        console.log("  Flow Explorer: https://evm-testnet.flowscan.io");
        console.log("  ETF Vault:");
        console.log(string.concat("    https://evm-testnet.flowscan.io/address/", vm.toString(deployment.etfVault)));
        console.log("  EIP-7702:");
        console.log(string.concat("    https://evm-testnet.flowscan.io/address/", vm.toString(deployment.eip7702Implementation)));
        
        console.log("\n5. Use the deployment-flow-etf.json file for addresses");
        console.log("\n6. Run tests with: forge test");
    }
}
