// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FlowTestAssets
 * @notice Simple test assets for Flow EVM ETF testing
 * @dev Includes basic faucet functionality for testing
 */

/**
 * @title WrappedFlow (WFLOW)
 * @notice Wrapped Flow token for ETF operations
 */
contract WrappedFlow is ERC20, Ownable {
    constructor(address owner) ERC20("Wrapped Flow", "WFLOW") Ownable(owner) {
        _mint(owner, 1_000_000 * 1e18); // 1M WFLOW initial supply
    }
    
    function faucet() external {
        _mint(msg.sender, 1000 * 1e18); // 1000 WFLOW per faucet call
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    // Allow wrapping FLOW -> WFLOW
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
    
    // Allow unwrapping WFLOW -> FLOW
    function withdraw(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
    
    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

/**
 * @title FlowUSDC (USDC)
 * @notice USDC stablecoin for Flow EVM
 */
contract FlowUSDC is ERC20, Ownable {
    constructor(address owner) ERC20("USD Coin", "USDC") Ownable(owner) {
        _mint(owner, 1_000_000 * 1e6); // 1M USDC initial supply
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function faucet() external {
        _mint(msg.sender, 10000 * 1e6); // 10000 USDC per faucet call
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

/**
 * @title FlowWETH (WETH)
 * @notice Wrapped Ethereum on Flow
 */
contract FlowWETH is ERC20, Ownable {
    constructor(address owner) ERC20("Wrapped Ethereum", "WETH") Ownable(owner) {
        _mint(owner, 10000 * 1e18); // 10K WETH initial supply
    }
    
    function faucet() external {
        _mint(msg.sender, 5 * 1e18); // 5 WETH per faucet call
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

/**
 * @title AnkrFlow (ankrFLOW)
 * @notice Liquid staked Flow token
 */
contract AnkrFlow is ERC20, Ownable {
    uint256 public stakingRatio = 1e18; // 1:1 ratio initially
    
    constructor(address owner) ERC20("Ankr Staked Flow", "ankrFLOW") Ownable(owner) {
        _mint(owner, 100000 * 1e18); // 100K ankrFLOW initial supply
    }
    
    function faucet() external {
        _mint(msg.sender, 500 * 1e18); // 500 ankrFLOW per faucet call
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    // Simulate staking FLOW for ankrFLOW
    function stake() external payable {
        uint256 ankrAmount = (msg.value * 1e18) / stakingRatio;
        _mint(msg.sender, ankrAmount);
    }
    
    // Simulate unstaking ankrFLOW for FLOW
    function unstake(uint256 ankrAmount) external {
        require(balanceOf(msg.sender) >= ankrAmount, "Insufficient balance");
        uint256 flowAmount = (ankrAmount * stakingRatio) / 1e18;
        _burn(msg.sender, ankrAmount);
        payable(msg.sender).transfer(flowAmount);
    }
    
    // Update staking ratio (simulates staking rewards)
    function updateStakingRatio(uint256 newRatio) external onlyOwner {
        stakingRatio = newRatio;
    }
    
    receive() external payable {
        uint256 ankrAmount = (msg.value * 1e18) / stakingRatio;
        _mint(msg.sender, ankrAmount);
    }
}

/**
 * @title TrumpFlow (TRUMP)
 * @notice Meme token for Flow EVM
 */
contract TrumpFlow is ERC20, Ownable {
    constructor(address owner) ERC20("Trump on Flow", "TRUMP") Ownable(owner) {
        _mint(owner, 1_000_000_000 * 1e18); // 1B TRUMP initial supply
    }
    
    function faucet() external {
        _mint(msg.sender, 100000 * 1e18); // 100K TRUMP per faucet call
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

/**
 * @title AssetFactory
 * @notice Factory to deploy and manage all test assets
 */
contract AssetFactory is Ownable {
    
    address public wflow;
    address public usdc;
    address public weth;
    address public ankrFlow;
    address public trump;
    
    event AssetDeployed(string name, address indexed asset);
    
    constructor(address owner) Ownable(owner) {}
    
    /**
     * @notice Deploy all test assets
     */
    function deployAssets() external onlyOwner {
        wflow = address(new WrappedFlow(owner()));
        emit AssetDeployed("WFLOW", wflow);
        
        usdc = address(new FlowUSDC(owner()));
        emit AssetDeployed("USDC", usdc);
        
        weth = address(new FlowWETH(owner()));
        emit AssetDeployed("WETH", weth);
        
        ankrFlow = address(new AnkrFlow(owner()));
        emit AssetDeployed("ankrFLOW", ankrFlow);
        
        trump = address(new TrumpFlow(owner()));
        emit AssetDeployed("TRUMP", trump);
    }
    
    /**
     * @notice Get all asset addresses
     */
    function getAssets() external view returns (
        address _wflow,
        address _usdc,
        address _weth,
        address _ankrFlow,
        address _trump
    ) {
        return (wflow, usdc, weth, ankrFlow, trump);
    }
    
    /**
     * @notice Fund user with test tokens
     * @param user User address to fund
     */
    function fundUser(address user) external {
        require(wflow != address(0), "Assets not deployed");
        
        // Call faucet functions for each asset
        WrappedFlow(payable(wflow)).faucet();
        FlowUSDC(usdc).faucet();
        FlowWETH(weth).faucet();
        AnkrFlow(payable(ankrFlow)).faucet();
        TrumpFlow(trump).faucet();
        
        // Transfer some tokens to the user if called by owner
        if (msg.sender == owner()) {
            WrappedFlow(payable(wflow)).transfer(user, 1000 * 1e18);
            FlowUSDC(usdc).transfer(user, 10000 * 1e6);
            FlowWETH(weth).transfer(user, 5 * 1e18);
            AnkrFlow(payable(ankrFlow)).transfer(user, 500 * 1e18);
            TrumpFlow(trump).transfer(user, 100000 * 1e18);
        }
    }
}
