// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FlowNativeAssets
 * @notice Flow-native test assets for ETF testing on Flow EVM
 * @dev Includes WFLOW, TRUMP, ankrFLOW and other Flow ecosystem tokens
 */

/**
 * @title WrappedFlow
 * @notice Wrapped Flow token for DeFi operations
 */
contract WrappedFlow is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e18; // 1B WFLOW
    
    constructor(address initialOwner) ERC20("Wrapped Flow", "WFLOW") Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function faucet() external {
        require(balanceOf(msg.sender) == 0, "Already claimed");
        _mint(msg.sender, 1000 * 1e18); // 1000 WFLOW
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
        _mint(msg.sender, msg.value); // Call the deposit function
    }
}

/**
 * @title TrumpFlow
 * @notice TRUMP meme token on Flow EVM
 */
contract TrumpFlow is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e18; // 1B TRUMP
    
    constructor(address initialOwner) ERC20("Trump on Flow", "TRUMP") Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function faucet() external {
        require(balanceOf(msg.sender) == 0, "Already claimed");
        _mint(msg.sender, 10000 * 1e18); // 10000 TRUMP
    }
}

/**
 * @title AnkrFlow
 * @notice Liquid staking token for Flow
 */
contract AnkrFlow is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 1e18; // 100M ankrFLOW
    uint256 public stakingRatio = 1e18; // 1:1 initially
    
    constructor(address initialOwner) ERC20("Ankr Staked Flow", "ankrFLOW") Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function faucet() external {
        require(balanceOf(msg.sender) == 0, "Already claimed");
        _mint(msg.sender, 500 * 1e18); // 500 ankrFLOW
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
}

/**
 * @title FlowUSDC
 * @notice USDC on Flow for DeFi operations
 */
contract FlowUSDC is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e6; // 1B USDC (6 decimals)
    
    constructor(address initialOwner) ERC20("USD Coin on Flow", "USDC") Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function faucet() external {
        require(balanceOf(msg.sender) == 0, "Already claimed");
        _mint(msg.sender, 10000 * 1e6); // 10000 USDC
    }
}

/**
 * @title FlowWETH
 * @notice Wrapped Ethereum on Flow
 */
contract FlowWETH is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18; // 1M WETH
    
    constructor(address initialOwner) ERC20("Wrapped Ethereum on Flow", "WETH") Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function faucet() external {
        require(balanceOf(msg.sender) == 0, "Already claimed");
        _mint(msg.sender, 5 * 1e18); // 5 WETH
    }
}

/**
 * @title FlowAssetFactory
 * @notice Factory contract to deploy and manage all Flow native assets
 */
contract FlowAssetFactory is Ownable {
    
    // Deployed asset addresses
    address public wflow;
    address public trump;
    address public ankrFlow;
    address public usdc;
    address public weth;
    
    event AssetDeployed(string name, address indexed asset);
    
    constructor(address initialOwner) Ownable(initialOwner) {}
    
    /**
     * @notice Deploy all Flow native assets
     */
    function deployAllAssets() external onlyOwner {
        wflow = address(new WrappedFlow(msg.sender));
        emit AssetDeployed("WFLOW", wflow);
        
        trump = address(new TrumpFlow(msg.sender));
        emit AssetDeployed("TRUMP", trump);
        
        ankrFlow = address(new AnkrFlow(msg.sender));
        emit AssetDeployed("ankrFLOW", ankrFlow);
        
        usdc = address(new FlowUSDC(msg.sender));
        emit AssetDeployed("USDC", usdc);
        
        weth = address(new FlowWETH(msg.sender));
        emit AssetDeployed("WETH", weth);
    }
    
    /**
     * @notice Get all deployed asset addresses
     */
    function getAllAssets() external view returns (
        address _wflow,
        address _trump,
        address _ankrFlow,
        address _usdc,
        address _weth
    ) {
        return (wflow, trump, ankrFlow, usdc, weth);
    }
    
    /**
     * @notice Fund user with test tokens from all assets
     */
    function fundUserWithTestTokens(address user) external {
        require(wflow != address(0), "Assets not deployed");
        
        // Just call the faucet functions for simplicity
        try WrappedFlow(payable(wflow)).faucet() {} catch {}
        try TrumpFlow(trump).faucet() {} catch {}
        try AnkrFlow(payable(ankrFlow)).faucet() {} catch {}
        try FlowUSDC(usdc).faucet() {} catch {}
        try FlowWETH(weth).faucet() {} catch {}
    }
    
    /**
     * @notice Setup initial liquidity and configurations
     * @dev This is a no-op as we're relying on the initial supply from the constructors
     */
    function setupInitialState() external {
        // No-op
    }
}
