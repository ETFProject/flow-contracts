// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20MockTokenFactory, MockERC20Token} from "../src/ERC20MockTokenFactory.sol";

contract DeployMockTokenFactory is Script {
    
    // Base network USDC address
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    // Token data structure
    struct TokenData {
        string name;
        string symbol;
        uint256 price; // Price in USDC (6 decimals)
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying from address:", deployer);
        console.log("USDC address:", USDC);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the factory
        ERC20MockTokenFactory factory = new ERC20MockTokenFactory(USDC, deployer);
        console.log("Factory deployed at:", address(factory));
        
        // Define all token data with realistic prices (in USDC with 6 decimals)
        TokenData[] memory tokens = new TokenData[](10);
        
        // Major cryptocurrencies with realistic prices
        tokens[0] = TokenData("Dogecoin", "DOGE", 0.4 * 1e6);        // $0.40
        tokens[1] = TokenData("Bitcoin", "BTC", 100000 * 1e6);       // $100,000
        tokens[2] = TokenData("Ethereum", "ETH", 3500 * 1e6);        // $3,500
        tokens[3] = TokenData("BNB", "BNB", 650 * 1e6);              // $650
        tokens[4] = TokenData("Solana", "SOL", 200 * 1e6);           // $200
        tokens[5] = TokenData("XRP", "XRP", 2.5 * 1e6);              // $2.50
        tokens[6] = TokenData("USD Coin", "USDC", 1 * 1e6);          // $1.00
        tokens[7] = TokenData("Cardano", "ADA", 1.2 * 1e6);          // $1.20
        tokens[8] = TokenData("Avalanche", "AVAX", 45 * 1e6);        // $45
        tokens[9] = TokenData("Shiba Inu", "SHIB", 0.00003 * 1e6);   // $0.00003
        
        // Deploy tokens in batches to avoid gas limits
        uint256 batchSize = 10;
        uint256 totalTokens = tokens.length;
        
        for (uint256 i = 0; i < totalTokens; i += batchSize) {
            uint256 endIndex = i + batchSize;
            if (endIndex > totalTokens) {
                endIndex = totalTokens;
            }
            
            uint256 currentBatchSize = endIndex - i;
            string[] memory names = new string[](currentBatchSize);
            string[] memory symbols = new string[](currentBatchSize);
            uint256[] memory prices = new uint256[](currentBatchSize);
            
            for (uint256 j = 0; j < currentBatchSize; j++) {
                names[j] = tokens[i + j].name;
                symbols[j] = tokens[i + j].symbol;
                prices[j] = tokens[i + j].price;
            }
            
            console.log("Deploying batch", (i / batchSize) + 1, "of", (totalTokens + batchSize - 1) / batchSize);
            address[] memory deployedTokens = factory.createMultipleTokens(names, symbols, prices);
            
            // Log deployed tokens in this batch
            for (uint256 k = 0; k < deployedTokens.length; k++) {
                console.log("Token deployed:", symbols[k], "at address:", deployedTokens[k]);
            }
        }
        
        // Add initial liquidity to all tokens
        console.log("Adding initial liquidity to tokens...");
        
        address[] memory allTokenAddresses = factory.getAllTokens();
        uint256[] memory liquidityAmounts = new uint256[](allTokenAddresses.length);
        
        // Add 10,000 USDC liquidity to each token
        for (uint256 i = 0; i < allTokenAddresses.length; i++) {
            liquidityAmounts[i] = 10000 * 1e6; // 10,000 USDC
        }
        
        // Note: In practice, you'd need to approve and have sufficient USDC
        // This is commented out as it requires actual USDC balance
        // factory.addUsdcLiquidityToMultiple(allTokenAddresses, liquidityAmounts);
        
        // Add token liquidity to each token (tokens are minted to deployer by default)
        // Commented out to avoid rate limiting issues
        /*
        for (uint256 i = 0; i < allTokenAddresses.length; i++) {
            MockERC20Token token = MockERC20Token(allTokenAddresses[i]);
            
            // Add 1000 tokens to each contract's liquidity
            token.addTokenLiquidity(1000 * 1e18);
            
            console.log("Added token liquidity to:", token.symbol());
        }
        */
        
        vm.stopBroadcast();
        
        // Final summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Factory address:", address(factory));
        console.log("Total tokens deployed:", factory.getTokenCount());
        console.log("USDC address:", USDC);
        console.log("Deployer address:", deployer);
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Add USDC liquidity to tokens using addUsdcLiquidity()");
        console.log("2. Update token prices as needed using updatePrice()");
        console.log("3. Users can now swap USDC for tokens using swapUsdcForToken()");
        
        // Save deployment info to a file (optional)
        string memory deploymentInfo = string(abi.encodePacked(
            "Factory: ", vm.toString(address(factory)), "\n",
            "USDC: ", vm.toString(USDC), "\n",
            "Deployer: ", vm.toString(deployer), "\n",
            "Total Tokens: ", vm.toString(factory.getTokenCount())
        ));
        
        vm.writeFile("deployment-mock-tokens.txt", deploymentInfo);
        console.log("Deployment info saved to deployment-mock-tokens.txt");
    }
    
    // Helper function to get deployment addresses (can be called separately)
    function getTokenAddresses(address factoryAddress) external view returns (address[] memory) {
        ERC20MockTokenFactory factory = ERC20MockTokenFactory(factoryAddress);
        return factory.getAllTokens();
    }
    
    // Helper function to get token info (can be called separately)
    function getTokenInfo(address factoryAddress, address tokenAddress) external view returns (
        string memory name,
        string memory symbol,
        uint256 price,
        uint256 usdcBalance,
        uint256 tokenBalance
    ) {
        ERC20MockTokenFactory factory = ERC20MockTokenFactory(factoryAddress);
        return factory.getTokenInfo(tokenAddress);
    }
}
