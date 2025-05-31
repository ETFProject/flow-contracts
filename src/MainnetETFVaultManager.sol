// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IAerodromeRouter.sol";

contract MainnetETFVaultManager {
    IAerodromeRouter public immutable aeroRouter;
    ERC20 public acceptedToken;
    address agentEOA;
    address factory;
    error Unauthorized();

    //The purpose of this contract is to manage stablecoin -> assets swaps when depositing and vice versa when withdrawing(base usdc?)
    //Only LLM wallet should have access to functions then
    //Share logic is handled on flow contracts
    // calculations can happen on backend, so that raw amounts would be called into functions
    //We have to option when bridging to set the recipient to any given address, so either llmwallet or this contract's address
    constructor(
        address _acceptedToken,
        address _agentEOA,
        address _factory,
        address _aeroRouter
    ) {
        acceptedToken = ERC20(_acceptedToken);
        agentEOA = _agentEOA;
        factory = _factory;
        aeroRouter = IAerodromeRouter(_aeroRouter);
    }

    function deposit(
        uint256 amount,
        address[] memory tokens,
        uint256[] memory weights
    ) public {
      acceptedToken.transferFrom(msg.sender,address(this),amount);
        //Make sure to transfer assets from LLMAgentWallet to this contract
        //For loop for swapping
        for (uint i = 0; i < tokens.length; i++) {
            swap(
                address(acceptedToken),
                tokens[i],
                weightsToRawAmount(weights[i], amount)
            );
        }
    }

    function withdraw(
        uint256[] memory amounts,
        address[] memory tokens
    ) public onlyAgent {
        for (uint256 i = 0; i < tokens.length; i++) {
            swap(tokens[i], address(acceptedToken), amounts[i]);
        }
        //Logic to expose/change allowances so that LLMAgent can bridge assets back to flow
    }

    function rebalance(
        uint256[] memory oldRawAmounts,
        address[] memory oldTokens,
        uint256[] memory newRawAmounts,
        address[] memory newTokens
    ) public onlyAgent {
        for (uint256 i = 0; i < oldTokens.length; i++) {
            swap(oldTokens[i], address(acceptedToken), oldRawAmounts[i]);
        }
        for (uint256 i = 0; i < newTokens.length; i++) {
            swap(address(acceptedToken), newTokens[i], newRawAmounts[i]);
        }
        //This one is a little tricky
        //Could maybe swap raw number of assets into stablecoin and then swap back into new assets
        //I think raw amounts is better actually, puts the impetus of logic handling onto flow contracts
    }

    modifier onlyAgent() {
        if (msg.sender != agentEOA) {
            revert Unauthorized();
        }
        _;
    }

    function weightsToRawAmount(
        uint256 weight,
        uint256 totalAmount
    ) public pure returns (uint256) {
        require(weight <= 10000, "Weight must be <= 10000");
        return (totalAmount * weight) / 10000;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256[] memory amounts) {
        // Approve the router to spend the tokens
        IERC20(tokenIn).approve(
            address(aeroRouter),
            amountIn
        );
        //create dynamyc array of RouteStruct and add token path
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](
            1
        );
        routes[0] = IAerodromeRouter.Route(tokenIn, tokenOut, false, factory);
        //getAmount out from trade
        uint256[] memory returnAmounts = aeroRouter.getAmountsOut(
            amountIn,
            routes
        );
        //call swap function
        amounts = aeroRouter.swapExactTokensForTokens( //swap usdc back to eth
            amountIn, //acceptedToken
            returnAmounts[1], //min usdc we want back,
            routes, //trade path,
            address(this), //receiver of the swap
            block.timestamp
        );
    }
}
