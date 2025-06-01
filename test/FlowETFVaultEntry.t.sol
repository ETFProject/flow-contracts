// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {FlowETFVaultEntry} from "../src/FlowETFVaultEntry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FlowETFVaultEntryTest is Test {
    FlowETFVaultEntry public vault;
    MockERC20 public mockToken;
    
    address public owner = makeAddr("owner");
    address public agentWallet = makeAddr("agentWallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    // Test constants
    uint256 public constant MIN_DEPOSIT = 1e15; // 0.001 FLOW
    uint256 public constant FLOW_CHAIN_ID = 545;

    function setUp() public {
        // Set the chain ID to Flow for testing
        vm.chainId(FLOW_CHAIN_ID);
        
        // Deploy the vault
        vm.prank(owner);
        vault = new FlowETFVaultEntry(
            "Flow ETF Token",
            "FETF",
            agentWallet,
            owner
        );
        
        // Deploy mock token for asset testing
        mockToken = new MockERC20("Mock Token", "MOCK");
        
        // Give users some ETH for testing
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(agentWallet, 10 ether);
    }

    // =============== DEPOSIT TESTS ===============

    function test_deposit_native_tokens() public {
        uint256 depositAmount = 1 ether;
        
        vm.prank(user1);
        uint256 shares = vault.deposit{value: depositAmount}();
        
        // Check shares minted
        assertEq(vault.balanceOf(user1), shares);
        assertEq(shares, depositAmount); // First deposit gets 1:1 ratio
        
        // Check total value locked
        assertEq(vault.totalValueLocked(), depositAmount);
        
        // Check agent wallet received the funds
        assertEq(agentWallet.balance, 10 ether + depositAmount);
    }

    function test_deposit_minimum_amount() public {
        uint256 depositAmount = MIN_DEPOSIT;
        
        vm.prank(user1);
        uint256 shares = vault.deposit{value: depositAmount}();
        
        assertEq(vault.balanceOf(user1), shares);
        assertEq(shares, depositAmount);
    }

    function test_deposit_revert_too_small() public {
        uint256 tooSmallAmount = MIN_DEPOSIT - 1;
        
        vm.prank(user1);
        vm.expectRevert("Amount too small");
        vault.deposit{value: tooSmallAmount}();
    }

    function test_deposit_multiple_users() public {
        // First user deposits
        uint256 firstDeposit = 2 ether;
        vm.prank(user1);
        uint256 shares1 = vault.deposit{value: firstDeposit}();
        
        // Second user deposits
        uint256 secondDeposit = 1 ether;
        vm.prank(user2);
        uint256 shares2 = vault.deposit{value: secondDeposit}();
        
        // Check shares allocation
        assertEq(vault.balanceOf(user1), shares1);
        assertEq(vault.balanceOf(user2), shares2);
        
        // Check total supply
        assertEq(vault.totalSupply(), shares1 + shares2);
        
        // Check total value locked
        assertEq(vault.totalValueLocked(), firstDeposit + secondDeposit);
    }

    function test_deposit_calculates_shares_correctly() public {
        // First deposit - gets 1:1 ratio
        uint256 firstDeposit = 2 ether;
        vm.prank(user1);
        uint256 shares1 = vault.deposit{value: firstDeposit}();
        assertEq(shares1, firstDeposit);
        
        // Send funds back to vault to maintain totalValue for calculation
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: firstDeposit}("");
        require(success, "Failed to send funds to vault");
        
        // Second deposit - should get proportional shares
        uint256 secondDeposit = 1 ether;
        vm.prank(user2);
        uint256 shares2 = vault.deposit{value: secondDeposit}();
        
        // The correct calculation is:
        // shares = (amount * totalSupply) / (totalValue + amount)
        // Because the deposit amount is added to totalValue during calculation
        // shares2 = (1 ether * 2 ether) / (2 ether + 1 ether) = 2/3 ether
        uint256 expectedShares2 = (secondDeposit * shares1) / (firstDeposit + secondDeposit);
        
        assertEq(shares2, expectedShares2);
        
        // Verify the math: 1 * 2 / 3 = 0.666... ether
        assertEq(expectedShares2, 666666666666666666);
    }

    // =============== WITHDRAW TESTS ===============

    function test_withdraw_native_tokens() public {
        // Setup: user deposits first
        uint256 depositAmount = 2 ether;
        vm.prank(user1);
        uint256 shares = vault.deposit{value: depositAmount}();
        
        // Simulate agent wallet sending funds back to vault for withdrawal
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "Failed to send funds to vault");
        
        uint256 initialBalance = user1.balance;
        uint256 withdrawShares = shares / 2; // Withdraw half
        
        vm.prank(user1);
        uint256 amountOut = vault.withdraw(withdrawShares, 0);
        
        // Check user received native tokens
        assertEq(user1.balance, initialBalance + amountOut);
        
        // Check shares burned
        assertEq(vault.balanceOf(user1), shares - withdrawShares);
        
        // Check total value locked updated
        assertEq(vault.totalValueLocked(), depositAmount - amountOut);
    }

    function test_withdraw_all_shares() public {
        // Setup: user deposits
        uint256 depositAmount = 1 ether;
        vm.prank(user1);
        uint256 shares = vault.deposit{value: depositAmount}();
        
        // Simulate agent wallet sending funds back to vault
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "Failed to send funds to vault");
        
        uint256 initialBalance = user1.balance;
        
        vm.prank(user1);
        uint256 amountOut = vault.withdraw(shares, 0);
        
        // Check user received all funds back
        assertEq(user1.balance, initialBalance + amountOut);
        
        // Check no shares remaining
        assertEq(vault.balanceOf(user1), 0);
        
        // Check total value locked is zero
        assertEq(vault.totalValueLocked(), 0);
    }

    function test_withdraw_revert_insufficient_shares() public {
        uint256 depositAmount = 1 ether;
        vm.prank(user1);
        uint256 shares = vault.deposit{value: depositAmount}();
        
        vm.prank(user1);
        vm.expectRevert("Insufficient shares");
        vault.withdraw(shares + 1, 0);
    }

    function test_withdraw_revert_slippage_protection() public {
        uint256 depositAmount = 1 ether;
        vm.prank(user1);
        uint256 shares = vault.deposit{value: depositAmount}();
        
        // Send funds back to vault
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "Failed to send funds to vault");
        
        vm.prank(user1);
        vm.expectRevert("Slippage too high");
        vault.withdraw(shares, depositAmount + 1); // Expect more than possible
    }

    function test_withdraw_revert_insufficient_native_balance() public {
        // User deposits and gets shares
        vm.prank(user1);
        uint256 shares = vault.deposit{value: 1 ether}();
        
        // Add some assets to the vault to increase totalValue
        // This way totalValue will be higher than vault's native balance
        vm.prank(agentWallet);
        vault.addAsset(address(mockToken), 5000); // 50% weight
        
        // Give vault some mock tokens
        mockToken.mint(address(vault), 1 ether);
        vm.prank(agentWallet);
        vault.updateAssetBalance(address(mockToken));
        
        // Send some native tokens back (but not enough for proportional withdrawal)
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: 0.3 ether}("");
        require(success, "Failed to send funds");
        
        // Now totalValue includes both native balance (0.3) + asset balance (1)
        // But user's shares represent proportion of higher total
        // The withdrawal should fail because native balance is insufficient
        vm.prank(user1);
        vm.expectRevert("Insufficient native balance");
        vault.withdraw(shares, 0);
    }

    // =============== VIEW FUNCTION TESTS ===============

    function test_getTotalValue_native_tokens() public {
        uint256 depositAmount = 2 ether;
        
        // Initially should be zero
        assertEq(vault.getTotalValue(), 0);
        
        // After deposit and sending funds back to vault
        vm.prank(user1);
        vault.deposit{value: depositAmount}();
        
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "Failed to send funds to vault");
        
        // Should equal the vault's native balance
        assertEq(vault.getTotalValue(), address(vault).balance);
    }

    function test_getNetAssetValue() public {
        // Initially should return 1e18 (default NAV)
        assertEq(vault.getNetAssetValue(), 1e18);
        
        uint256 depositAmount = 2 ether;
        vm.prank(user1);
        vault.deposit{value: depositAmount}();
        
        // Send funds back to vault
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "Failed to send funds to vault");
        
        // NAV should be (totalValue * 1e18) / totalSupply
        uint256 expectedNav = (vault.getTotalValue() * 1e18) / vault.totalSupply();
        assertEq(vault.getNetAssetValue(), expectedNav);
    }

    // =============== EDGE CASE TESTS ===============

    function test_multiple_deposits_and_withdrawals() public {
        // User1 deposits
        vm.prank(user1);
        uint256 shares1 = vault.deposit{value: 2 ether}();
        
        // User2 deposits
        vm.prank(user2);
        uint256 shares2 = vault.deposit{value: 1 ether}();
        
        // Send funds back to vault for withdrawals
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: 3 ether}("");
        require(success, "Failed to send funds to vault");
        
        uint256 user1InitialBalance = user1.balance;
        uint256 user2InitialBalance = user2.balance;
        
        // User1 withdraws half
        vm.prank(user1);
        uint256 amountOut1 = vault.withdraw(shares1 / 2, 0);
        
        // User2 withdraws all
        vm.prank(user2);
        uint256 amountOut2 = vault.withdraw(shares2, 0);
        
        // Check balances
        assertEq(user1.balance, user1InitialBalance + amountOut1);
        assertEq(user2.balance, user2InitialBalance + amountOut2);
        
        // Check remaining shares
        assertEq(vault.balanceOf(user1), shares1 - shares1 / 2);
        assertEq(vault.balanceOf(user2), 0);
    }

    function test_deposit_zero_amount() public {
        vm.prank(user1);
        vm.expectRevert("Amount too small");
        vault.deposit{value: 0}();
    }

    function test_withdraw_zero_shares() public {
        vm.prank(user1);
        vm.expectRevert("Invalid shares");
        vault.withdraw(0, 0);
    }

    // =============== ACCESS CONTROL TESTS ===============

    function test_deposit_when_paused() public {
        vm.prank(owner);
        vault.emergencyPause();
        
        vm.prank(user1);
        vm.expectRevert();
        vault.deposit{value: 1 ether}();
    }

    function test_withdraw_when_paused() public {
        // Setup: deposit first
        vm.prank(user1);
        uint256 shares = vault.deposit{value: 1 ether}();
        
        // Pause the contract
        vm.prank(owner);
        vault.emergencyPause();
        
        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(shares, 0);
    }

    // =============== INTEGRATION TESTS ===============

    function test_full_deposit_withdraw_cycle() public {
        uint256 depositAmount = 5 ether;
        uint256 initialBalance = user1.balance;
        
        // Deposit
        vm.prank(user1);
        uint256 shares = vault.deposit{value: depositAmount}();
        
        assertEq(user1.balance, initialBalance - depositAmount);
        assertEq(vault.balanceOf(user1), shares);
        
        // Send funds back to vault (simulating agent operations)
        vm.prank(agentWallet);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "Failed to send funds to vault");
        
        // Withdraw all
        vm.prank(user1);
        uint256 amountOut = vault.withdraw(shares, 0);
        
        // Should get back the same amount (minus gas costs)
        assertEq(user1.balance, initialBalance - depositAmount + amountOut);
        assertEq(vault.balanceOf(user1), 0);
        assertApproxEqAbs(amountOut, depositAmount, 1); // Allow for small rounding
    }

    // =============== HELPER FUNCTIONS ===============

    function test_receive_function() public {
        uint256 amount = 1 ether;
        
        vm.prank(user1);
        (bool success,) = address(vault).call{value: amount}("");
        
        assertTrue(success);
        assertEq(address(vault).balance, amount);
    }
}