// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/FlowTestAssets.sol";

/**
 * @title TestSimpleDeployment
 * @notice Simple deployment script to test Flow EVM deployment
 */
contract TestSimpleDeployment is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "FLOW");
        console.log("Chain ID:", block.chainid);
        console.log("Block number:", block.number);
        
        vm.startBroadcast(deployerPrivateKey);
        
        try new AssetFactory(deployer) returns (AssetFactory factory) {
            console.log("SUCCESS: AssetFactory deployed at:", address(factory));
            
            try factory.deployAssets() {
                console.log("SUCCESS: Assets deployed");
                
                (
                    address wflow,
                    address usdc,
                    address weth,
                    address ankrFlow,
                    address trump
                ) = factory.getAssets();
                
                console.log("WFLOW:", wflow);
                console.log("USDC:", usdc);
                console.log("WETH:", weth);
                console.log("ankrFLOW:", ankrFlow);
                console.log("TRUMP:", trump);
                
            } catch Error(string memory reason) {
                console.log("FAILED to deploy assets:", reason);
            } catch (bytes memory lowLevelData) {
                console.log("FAILED to deploy assets - low level error");
                console.logBytes(lowLevelData);
            }
            
        } catch Error(string memory reason) {
            console.log("FAILED to deploy AssetFactory:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED to deploy AssetFactory - low level error");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
    }
}
