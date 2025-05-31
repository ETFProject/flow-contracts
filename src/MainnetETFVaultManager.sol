// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract MainnetETFVaultManager {
    ERC20 public acceptedToken;

    //The purpose of this contract is to manage stablecoin -> assets swaps when depositing and vice versa when withdrawing(base usdc?)
    //Only LLM wallet should have access to functions then
    //Share logic is handled on flow contracts
    // calculations can happen on backend, so that raw amounts would be called into functions
    //We have to option when bridging to set the recipient to any given address, so either llmwallet or this contract's address
    constructor(address _acceptedToken) public {
        acceptedToken = ERC20(_acceptedToken);
    }

    function deposit(
        uint256 amount,
        address[] tokens,
        uint256[] weights
    ) onlyAgent {
        //For loop for swapping
        for (uint i = 0; i < tokens.length; i++) {
            swap(
                address(acceptedToken),
                tokens[i],
                weightsToRawAmount(weights[i], amount)
            );
        }
    }

    function withdraw(uint256[] amounts, address[] tokens) onlyAgent {
        for (uint256 i = 0; i < tokens.length; i++) {
            swap(tokens[i], acceptedToken, amounts);
        }
    }

    function rebalance() onlyAgent {}

    function weightsToRawAmount(
        uint256 weight,
        uint256 totalAmount
    ) returns (uint256) {
        require(weight <= 10000, "Weight must be <= 10000");
        return (totalAmount * weight) / 10000;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public returns (uint256[] memory amounts) {
        //transfer tokens from sender to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // Approve the router to spend the tokens
        weth.approve(address(aeroRouter), weth.balanceOf(address(this)));
        //create dynamyc array of RouteStruct and add token path
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(tokenIn, tokenOut, false, factory);
        //getAmount out from trade
        uint256[] memory returnAmounts = aeroRouter.getAmountsOut(
            amountIn,
            routes
        );
        //call swap function
        amounts = aeroRouter.swapExactTokensForTokens( //swap usdc back to eth
            amountIn, //weth
            returnAmounts[1], //min usdc we want back,
            routes, //trade path,
            msg.sender, //receiver of the swap
            block.timestamp
        );
    }
}
