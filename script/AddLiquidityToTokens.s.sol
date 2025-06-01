// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20MockTokenFactory, MockERC20Token} from "../src/ERC20MockTokenFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AddLiquidityToTokens is Script {
    
    // Base network USDC address
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get factory address from environment or set manually
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        
        console.log("Adding liquidity from address:", deployer);
        console.log("Factory address:", factoryAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        ERC20MockTokenFactory factory = ERC20MockTokenFactory(factoryAddress);
        IERC20 usdc = IERC20(USDC);
        
        // Get all token addresses
        address[] memory tokenAddresses = factory.getAllTokens();
        console.log("Found", tokenAddresses.length, "tokens");
        
        // Check deployer's USDC balance
        uint256 usdcBalance = usdc.balanceOf(deployer);
        console.log("Deployer USDC balance:", usdcBalance);
        
        uint256 liquidityPerToken = 5000 * 1e6; // 5,000 USDC per token
        uint256 totalUsdcNeeded = liquidityPerToken * tokenAddresses.length;
        
        require(usdcBalance >= totalUsdcNeeded, "Insufficient USDC balance");
        
        // Add USDC liquidity to each token individually
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            MockERC20Token token = MockERC20Token(tokenAddresses[i]);
            
            console.log("Adding liquidity to:", token.symbol());
            
            // Approve USDC for the token
            usdc.approve(address(token), liquidityPerToken);
            
            // Add USDC liquidity
            token.addUsdcLiquidity(liquidityPerToken);
            
            // Add token liquidity (500 tokens)
            token.addTokenLiquidity(500 * 1e18);
            
            //console.log("Liquidity added to", token.symbol(), "- USDC:", liquidityPerToken, "Tokens: 500");
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== LIQUIDITY SUMMARY ===");
        console.log("USDC liquidity per token:", liquidityPerToken);
        console.log("Token liquidity per token: 500");
        console.log("Total tokens with liquidity:", tokenAddresses.length);
        console.log("Total USDC used:", totalUsdcNeeded);
    }
    
    // Helper function to add liquidity to specific tokens
    function addLiquidityToSpecificTokens(
        address factoryAddress,
        string[] memory symbols,
        uint256 usdcAmount,
        uint256 tokenAmount
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        ERC20MockTokenFactory factory = ERC20MockTokenFactory(factoryAddress);
        IERC20 usdc = IERC20(USDC);
        
        address[] memory allTokens = factory.getAllTokens();
        
        for (uint256 i = 0; i < symbols.length; i++) {
            // Find token by symbol
            for (uint256 j = 0; j < allTokens.length; j++) {
                MockERC20Token token = MockERC20Token(allTokens[j]);
                
                if (keccak256(bytes(token.symbol())) == keccak256(bytes(symbols[i]))) {
                    console.log("Adding liquidity to:", symbols[i]);
                    
                    usdc.approve(address(token), usdcAmount);
                    token.addUsdcLiquidity(usdcAmount);
                    token.addTokenLiquidity(tokenAmount);
                    
                    break;
                }
            }
        }
        
        vm.stopBroadcast();
    }
}
