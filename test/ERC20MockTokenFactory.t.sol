// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20MockTokenFactory, MockERC20Token} from "../src/ERC20MockTokenFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1000000 * 10**6); // 1M USDC with 6 decimals
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ERC20MockTokenFactoryTest is Test {
    ERC20MockTokenFactory public factory;
    MockUSDC public usdc;
    MockERC20Token public token1;
    MockERC20Token public token2;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    // Test constants
    uint256 public constant INITIAL_PRICE_1 = 2 * 1e6; // 2 USDC per token
    uint256 public constant INITIAL_PRICE_2 = 0.5 * 1e6; // 0.5 USDC per token
    uint256 public constant USDC_AMOUNT = 1000 * 1e6; // 1000 USDC
    
    function setUp() public {
        // Deploy USDC mock
        usdc = new MockUSDC();
        
        // Deploy factory
        vm.prank(owner);
        factory = new ERC20MockTokenFactory(address(usdc), owner);
        
        // Create test tokens
        vm.prank(owner);
        address token1Addr = factory.createToken("Test Token 1", "TT1", INITIAL_PRICE_1);
        token1 = MockERC20Token(token1Addr);
        
        vm.prank(owner);
        address token2Addr = factory.createToken("Test Token 2", "TT2", INITIAL_PRICE_2);
        token2 = MockERC20Token(token2Addr);
        
        // Give users some USDC
        usdc.mint(user1, USDC_AMOUNT);
        usdc.mint(user2, USDC_AMOUNT);
        usdc.mint(owner, USDC_AMOUNT * 10);
        
        // Add initial liquidity to tokens
        vm.startPrank(owner);
        usdc.approve(address(token1), USDC_AMOUNT);
        usdc.approve(address(token2), USDC_AMOUNT);
        token1.addUsdcLiquidity(USDC_AMOUNT / 2);
        token2.addUsdcLiquidity(USDC_AMOUNT / 2);
        
        // Add token liquidity
        token1.addTokenLiquidity(100 * 1e18); // 100 tokens
        token2.addTokenLiquidity(100 * 1e18); // 100 tokens
        vm.stopPrank();
    }

    // =============== FACTORY TESTS ===============

    function test_factory_deployment() public {
        assertEq(address(factory.usdc()), address(usdc));
        assertEq(factory.owner(), owner);
        assertEq(factory.getTokenCount(), 2);
    }

    function test_create_token() public {
        vm.prank(owner);
        address newTokenAddr = factory.createToken("New Token", "NEW", 1e6);
        
        MockERC20Token newToken = MockERC20Token(newTokenAddr);
        
        assertEq(newToken.name(), "New Token");
        assertEq(newToken.symbol(), "NEW");
        assertEq(newToken.getPrice(), 1e6);
        assertEq(newToken.owner(), owner);
        assertTrue(factory.isTokenValid(newTokenAddr));
        assertEq(factory.getTokenCount(), 3);
    }

    function test_create_multiple_tokens() public {
        string[] memory names = new string[](2);
        names[0] = "Token A";
        names[1] = "Token B";
        
        string[] memory symbols = new string[](2);
        symbols[0] = "TKA";
        symbols[1] = "TKB";
        
        uint256[] memory prices = new uint256[](2);
        prices[0] = 3 * 1e6;
        prices[1] = 4 * 1e6;
        
        vm.startPrank(owner);
        address[] memory newTokens = factory.createMultipleTokens(names, symbols, prices);
        vm.stopPrank();
        
        assertEq(newTokens.length, 2);
        assertEq(MockERC20Token(newTokens[0]).name(), "Token A");
        assertEq(MockERC20Token(newTokens[1]).name(), "Token B");
        assertEq(factory.getTokenCount(), 4);
    }

    function test_create_token_revert_non_owner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.createToken("Bad Token", "BAD", 1e6);
    }

    function test_get_all_tokens() public {
        address[] memory allTokens = factory.getAllTokens();
        assertEq(allTokens.length, 2);
        assertEq(allTokens[0], address(token1));
        assertEq(allTokens[1], address(token2));
    }

    function test_get_token_info() public {
        (
            string memory name,
            string memory symbol,
            uint256 price,
            uint256 usdcBalance,
            uint256 tokenBalance
        ) = factory.getTokenInfo(address(token1));
        
        assertEq(name, "Test Token 1");
        assertEq(symbol, "TT1");
        assertEq(price, INITIAL_PRICE_1);
        assertEq(usdcBalance, USDC_AMOUNT / 2);
        assertEq(tokenBalance, 100 * 1e18);
    }

    // =============== TOKEN SWAP TESTS ===============

    function test_swap_usdc_for_token() public {
        uint256 usdcAmount = 10 * 1e6; // 10 USDC
        uint256 expectedTokens = token1.getUsdcToTokenQuote(usdcAmount);
        
        vm.startPrank(user1);
        usdc.approve(address(token1), usdcAmount);
        uint256 tokensReceived = token1.swapUsdcForToken(usdcAmount, 0);
        vm.stopPrank();
        
        assertEq(tokensReceived, expectedTokens);
        assertEq(token1.balanceOf(user1), tokensReceived);
        assertEq(usdc.balanceOf(user1), USDC_AMOUNT - usdcAmount);
        
        // Verify math: 10 USDC / 2 USDC per token = 5 tokens
        assertEq(tokensReceived, 5 * 1e18);
    }

    function test_swap_token_for_usdc() public {
        // First get some tokens
        uint256 usdcAmount = 10 * 1e6;
        vm.startPrank(user1);
        usdc.approve(address(token1), usdcAmount);
        uint256 tokensReceived = token1.swapUsdcForToken(usdcAmount, 0);
        
        // Now swap tokens back for USDC
        uint256 tokensToSwap = tokensReceived / 2; // Swap half
        uint256 expectedUsdc = token1.getTokenToUsdcQuote(tokensToSwap);
        
        uint256 usdcReceived = token1.swapTokenForUsdc(tokensToSwap, 0);
        vm.stopPrank();
        
        assertEq(usdcReceived, expectedUsdc);
        assertEq(token1.balanceOf(user1), tokensReceived - tokensToSwap);
        
        // Verify math: 2.5 tokens * 2 USDC per token = 5 USDC
        assertEq(usdcReceived, 5 * 1e6);
    }

    function test_swap_different_prices() public {
        uint256 usdcAmount = 10 * 1e6; // 10 USDC
        
        // Token1: 2 USDC per token -> 5 tokens
        vm.startPrank(user1);
        usdc.approve(address(token1), usdcAmount);
        uint256 tokens1 = token1.swapUsdcForToken(usdcAmount, 0);
        vm.stopPrank();
        
        // Token2: 0.5 USDC per token -> 20 tokens
        vm.startPrank(user2);
        usdc.approve(address(token2), usdcAmount);
        uint256 tokens2 = token2.swapUsdcForToken(usdcAmount, 0);
        vm.stopPrank();
        
        assertEq(tokens1, 5 * 1e18);
        assertEq(tokens2, 20 * 1e18);
    }

    function test_swap_slippage_protection() public {
        uint256 usdcAmount = 10 * 1e6;
        uint256 expectedTokens = token1.getUsdcToTokenQuote(usdcAmount);
        
        vm.startPrank(user1);
        usdc.approve(address(token1), usdcAmount);
        
        // Should revert if minimum is too high
        vm.expectRevert("Slippage protection: insufficient output");
        token1.swapUsdcForToken(usdcAmount, expectedTokens + 1);
        
        // Should succeed with reasonable minimum
        uint256 tokensReceived = token1.swapUsdcForToken(usdcAmount, expectedTokens);
        assertEq(tokensReceived, expectedTokens);
        vm.stopPrank();
    }

    function test_swap_insufficient_liquidity() public {
        // Calculate USDC amount needed to exceed token balance
        // We have 100 tokens, price is 2 USDC per token
        // So we need more than 200 USDC to exceed token balance
        uint256 largeAmount = 250 * 1e6; // 250 USDC should require 125 tokens (more than 100 available)
        
        vm.startPrank(user1);
        usdc.approve(address(token1), largeAmount);
        
        vm.expectRevert("Insufficient token liquidity");
        token1.swapUsdcForToken(largeAmount, 0);
        vm.stopPrank();
    }

    // =============== PRICE UPDATE TESTS ===============

    function test_update_price() public {
        uint256 newPrice = 3 * 1e6; // 3 USDC per token
        
        vm.prank(owner);
        token1.updatePrice(newPrice);
        
        assertEq(token1.getPrice(), newPrice);
        
        // Test that quotes reflect new price
        uint256 usdcAmount = 9 * 1e6; // 9 USDC
        uint256 expectedTokens = token1.getUsdcToTokenQuote(usdcAmount);
        assertEq(expectedTokens, 3 * 1e18); // 9 / 3 = 3 tokens
    }

    function test_update_price_revert_non_owner() public {
        vm.prank(user1);
        vm.expectRevert();
        token1.updatePrice(5 * 1e6);
    }

    function test_update_multiple_prices() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory newPrices = new uint256[](2);
        newPrices[0] = 4 * 1e6;
        newPrices[1] = 1 * 1e6;
        
        // Update prices via factory batch function
        vm.startPrank(owner);
        factory.updateMultiplePrices(tokens, newPrices);
        vm.stopPrank();
        
        assertEq(token1.getPrice(), 4 * 1e6);
        assertEq(token2.getPrice(), 1 * 1e6);
    }

    // =============== LIQUIDITY MANAGEMENT TESTS ===============

    function test_add_remove_usdc_liquidity() public {
        uint256 addAmount = 100 * 1e6;
        uint256 initialBalance = token1.getUsdcBalance();
        
        vm.startPrank(owner);
        usdc.approve(address(token1), addAmount);
        token1.addUsdcLiquidity(addAmount);
        
        assertEq(token1.getUsdcBalance(), initialBalance + addAmount);
        
        // Remove liquidity
        token1.removeUsdcLiquidity(addAmount);
        assertEq(token1.getUsdcBalance(), initialBalance);
        vm.stopPrank();
    }

    function test_add_remove_token_liquidity() public {
        uint256 addAmount = 50 * 1e18;
        uint256 initialBalance = token1.getTokenBalance();
        
        vm.prank(owner);
        token1.addTokenLiquidity(addAmount);
        
        assertEq(token1.getTokenBalance(), initialBalance + addAmount);
        
        // Remove liquidity
        vm.prank(owner);
        token1.removeTokenLiquidity(addAmount);
        assertEq(token1.getTokenBalance(), initialBalance);
    }

    // =============== QUOTE TESTS ===============

    function test_usdc_to_token_quote() public {
        uint256 usdcAmount = 20 * 1e6; // 20 USDC
        uint256 quote = token1.getUsdcToTokenQuote(usdcAmount);
        
        // 20 USDC / 2 USDC per token = 10 tokens
        assertEq(quote, 10 * 1e18);
    }

    function test_token_to_usdc_quote() public {
        uint256 tokenAmount = 15 * 1e18; // 15 tokens
        uint256 quote = token1.getTokenToUsdcQuote(tokenAmount);
        
        // 15 tokens * 2 USDC per token = 30 USDC
        assertEq(quote, 30 * 1e6);
    }

    function test_quote_zero_amounts() public {
        assertEq(token1.getUsdcToTokenQuote(0), 0);
        assertEq(token1.getTokenToUsdcQuote(0), 0);
    }

    // =============== EDGE CASE TESTS ===============

    function test_decimal_precision() public {
        // Test with fractional USDC amounts
        uint256 usdcAmount = 1.5 * 1e6; // 1.5 USDC
        uint256 expectedTokens = token1.getUsdcToTokenQuote(usdcAmount);
        
        vm.startPrank(user1);
        usdc.approve(address(token1), usdcAmount);
        uint256 tokensReceived = token1.swapUsdcForToken(usdcAmount, 0);
        vm.stopPrank();
        
        assertEq(tokensReceived, expectedTokens);
        // 1.5 USDC / 2 USDC per token = 0.75 tokens
        assertEq(tokensReceived, 0.75 * 1e18);
    }

    function test_round_trip_swap() public {
        uint256 initialUsdc = usdc.balanceOf(user1);
        uint256 usdcAmount = 10 * 1e6;
        
        vm.startPrank(user1);
        
        // Swap USDC for tokens
        usdc.approve(address(token1), usdcAmount);
        uint256 tokensReceived = token1.swapUsdcForToken(usdcAmount, 0);
        
        // Swap tokens back for USDC
        uint256 usdcReceived = token1.swapTokenForUsdc(tokensReceived, 0);
        
        vm.stopPrank();
        
        // Should get back the same amount (minus any rounding)
        assertEq(usdcReceived, usdcAmount);
        assertEq(usdc.balanceOf(user1), initialUsdc - usdcAmount + usdcReceived);
    }

    function test_multiple_users_swapping() public {
        uint256 usdcAmount = 5 * 1e6;
        
        // User1 swaps
        vm.startPrank(user1);
        usdc.approve(address(token1), usdcAmount);
        uint256 tokens1 = token1.swapUsdcForToken(usdcAmount, 0);
        vm.stopPrank();
        
        // User2 swaps
        vm.startPrank(user2);
        usdc.approve(address(token1), usdcAmount);
        uint256 tokens2 = token1.swapUsdcForToken(usdcAmount, 0);
        vm.stopPrank();
        
        // Both should get same amount
        assertEq(tokens1, tokens2);
        assertEq(tokens1, 2.5 * 1e18); // 5 USDC / 2 USDC per token = 2.5 tokens
        
        // Verify balances
        assertEq(token1.balanceOf(user1), tokens1);
        assertEq(token1.balanceOf(user2), tokens2);
    }

    // =============== INTEGRATION TESTS ===============

    function test_factory_batch_operations() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50 * 1e6;
        amounts[1] = 75 * 1e6;
        
        uint256 totalAmount = amounts[0] + amounts[1];
        
        vm.startPrank(owner);
        usdc.approve(address(factory), totalAmount);
        factory.addUsdcLiquidityToMultiple(tokens, amounts);
        vm.stopPrank();
        
        // Verify liquidity was added
        assertTrue(token1.getUsdcBalance() >= amounts[0]);
        assertTrue(token2.getUsdcBalance() >= amounts[1]);
    }
}