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
    address wbtc;
    address shib;
    address wif;
    

    function setUp() public {
        manager = new MainnetETFVaultManager(usdc, alice, factory, aeroRouter);
    }

    function test_deposit() public {
      vm.prank(alice);
      uint256 tokenAmt = 1000000;
      deal(usdc,alice, tokenAmt);
      IERC20 USDC = IERC20(usdc);
      USDC.approve(address(manager),tokenAmt);

      address[] memory tokens = new address[] (3);
      tokens[0] = wbtc;
      tokens[1] = shib;
      tokens[2] = wif;
      uint256[] memory weights = new uint256[] (3);
      weights[0] = 5000;
      weights[1] = 3000;
      weights[2] = 2000;

      manager.deposit(tokenAmt,tokens,weights);
    }

    function test_withdraw() public {
      //manager.withdraw();
    }

    function test_rebalance() public {
      //manager.rebalance();
    }
}
