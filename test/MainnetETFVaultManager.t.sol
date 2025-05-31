// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {MainnetETFVaultManager} from "../src/MainnetETFVaultManager.sol";

contract CounterTest is Test {
    MainnetETFVaultManager manager;
    address public usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public alice = address(0xace);
    address public factory = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address public aeroRouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    function setUp() public {
        manager = new MainnetETFVaultManager(usdc, alice, factory, aeroRouter);
    }

    function test_deposit() public {
      manager.deposit();
    }

    function test_withdraw() public {
      manager.withdraw();
    }

    function test_rebalance() public {
      manager.rebalance();
    }
}
