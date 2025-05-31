// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {MainnetETFVaultManager} from "../src/MainnetETFVaultManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MainnetETFVaultManagerTest is Test {
    MainnetETFVaultManager manager;
    address public usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public alice = makeAddr("alice");
    address public factory = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address public aeroRouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address wbtc = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // Base WBTC
    address weth = 0x4200000000000000000000000000000000000006; // Base SHIB  
    address doge = 0x67f0870BB897F5E1c369976b4A2962d527B9562c; // Base WIF
    

    function setUp() public {
        // Fork Base mainnet for testing
        vm.createSelectFork("https://mainnet.base.org");
        manager = new MainnetETFVaultManager(usdc, alice, factory, aeroRouter);
    }

    function test_deposit() public {
      uint256 tokenAmt = 1000000;
      deal(usdc,alice, tokenAmt);
      IERC20 USDC = IERC20(usdc);
      
      vm.startPrank(alice);
      USDC.approve(address(manager),tokenAmt);

      // Test with just WBTC which is more likely to have liquidity
      address[] memory tokens = new address[] (3);
      tokens[0] = wbtc;
      tokens[1] = weth;
      tokens[2] = doge;
      uint256[] memory weights = new uint256[] (3);
      weights[0] = 5000; // 100%
      weights[1] = 3000;
      weights[2] = 2000;

      manager.deposit(tokenAmt,tokens,weights);
      vm.stopPrank();
      assertNotEq(0, IERC20(wbtc).balanceOf(address(manager)));
      assertNotEq(0, IERC20(weth).balanceOf(address(manager)));
      assertNotEq(0, IERC20(doge).balanceOf(address(manager)));

      }

    function test_withdraw() public {
      //manager.withdraw();
    }

    function test_rebalance() public {
      //manager.rebalance();
    }
}
