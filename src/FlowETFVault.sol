// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FlowETFVault
 * @notice Clean ETF Vault for Flow EVM with agent wallet control
 * @dev Designed for Flow EVM (Chain ID: 545) with EIP-7702 delegation support
 *      Features: Multi-asset ETF, agent wallet control, cross-chain fund management
 */
contract FlowETFVault is ERC20, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============== CONSTANTS ===============
    
    uint256 public constant FLOW_CHAIN_ID = 545;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_DEPOSIT = 1e15; // 0.001 FLOW
    uint256 public constant MAX_ASSETS = 10; // Maximum number of assets
    
    // =============== STRUCTS ===============
    
    struct Asset {
        address token;
        uint256 targetWeight; // In basis points (1% = 100)
        uint256 balance;
        bool active;
    }
    
    // =============== STATE VARIABLES ===============
    
    // Agent wallet management
    address public agentWallet;
    mapping(address => bool) public authorizedAgents;
    
    // ETF assets
    Asset[] public assets;
    mapping(address => uint256) public assetIndex; // token => index in assets array
    mapping(address => bool) public supportedTokens;
    
    // Cross-chain management
    mapping(uint256 => address) public chainVaults; // chainId => vault address
    mapping(uint256 => bool) public supportedChains;
    
    // Performance tracking
    uint256 public totalValueLocked;
    uint256 public lastRebalanceTime;
    
    // =============== EVENTS ===============
    
    event AgentWalletSet(address indexed oldAgent, address indexed newAgent);
    event AgentAuthorized(address indexed agent, bool authorized);
    event AssetAdded(address indexed token, uint256 targetWeight);
    event AssetRemoved(address indexed token);
    event AssetRebalanced(address indexed token, uint256 newBalance);
    event CrossChainTransfer(uint256 indexed chainId, address indexed token, uint256 amount);
    event FundsMovedToProtocol(address indexed protocol, address indexed token, uint256 amount);
    event FundsRetrievedFromProtocol(address indexed protocol, address indexed token, uint256 amount);
    
    // =============== ERRORS ===============
    
    error Unauthorized();
    error InvalidAgent();
    error InvalidAsset();
    error InvalidWeight();
    error TooManyAssets();
    error AssetNotSupported();
    error InsufficientBalance();
    error InvalidChain();
    
    // =============== MODIFIERS ===============
    
    modifier onlyAgent() {
        if (msg.sender != agentWallet && !authorizedAgents[msg.sender]) {
            revert Unauthorized();
        }
        _;
    }
    
    modifier validAsset(address token) {
        if (!supportedTokens[token]) revert AssetNotSupported();
        _;
    }
    
    modifier validChain() {
        if (block.chainid != FLOW_CHAIN_ID) revert InvalidChain();
        _;
    }
    
    // =============== CONSTRUCTOR ===============
    
    constructor(
        string memory name,
        string memory symbol,
        address _agentWallet,
        address _owner
    ) ERC20(name, symbol) Ownable(_owner) validChain {
        if (_agentWallet == address(0)) revert InvalidAgent();
        
        agentWallet = _agentWallet;
        authorizedAgents[_agentWallet] = true;
        lastRebalanceTime = block.timestamp;
        
        emit AgentWalletSet(address(0), _agentWallet);
    }
    
    // =============== AGENT MANAGEMENT ===============
    
    /**
     * @notice Set new primary agent wallet
     * @param newAgent New agent wallet address
     */
    function setAgentWallet(address newAgent) external onlyOwner {
        if (newAgent == address(0)) revert InvalidAgent();
        
        address oldAgent = agentWallet;
        agentWallet = newAgent;
        authorizedAgents[newAgent] = true;
        
        emit AgentWalletSet(oldAgent, newAgent);
    }
    
    /**
     * @notice Authorize/deauthorize additional agent addresses
     * @param agent Agent address
     * @param authorized Authorization status
     */
    function setAgentAuthorization(address agent, bool authorized) external onlyOwner {
        authorizedAgents[agent] = authorized;
        emit AgentAuthorized(agent, authorized);
    }
    
    // =============== ASSET MANAGEMENT ===============
    
    /**
     * @notice Add a new asset to the ETF
     * @param token Token address
     * @param targetWeight Target weight in basis points
     */
    function addAsset(address token, uint256 targetWeight) external onlyAgent {
        if (token == address(0)) revert InvalidAsset();
        if (targetWeight == 0 || targetWeight > BASIS_POINTS) revert InvalidWeight();
        if (supportedTokens[token]) revert InvalidAsset(); // Already exists
        if (assets.length >= MAX_ASSETS) revert TooManyAssets();
        
        // Check total weights don't exceed 100%
        uint256 totalWeight = getTotalTargetWeight() + targetWeight;
        if (totalWeight > BASIS_POINTS) revert InvalidWeight();
        
        assets.push(Asset({
            token: token,
            targetWeight: targetWeight,
            balance: 0,
            active: true
        }));
        
        assetIndex[token] = assets.length - 1;
        supportedTokens[token] = true;
        
        emit AssetAdded(token, targetWeight);
    }
    
    /**
     * @notice Remove asset from ETF
     * @param token Token address to remove
     */
    function removeAsset(address token) external onlyAgent validAsset(token) {
        uint256 index = assetIndex[token];
        assets[index].active = false;
        supportedTokens[token] = false;
        
        emit AssetRemoved(token);
    }
    
    /**
     * @notice Update asset balance after rebalancing
     * @param token Token address
     */
    function updateAssetBalance(address token) external onlyAgent validAsset(token) {
        uint256 index = assetIndex[token];
        uint256 currentBalance = IERC20(token).balanceOf(address(this));
        assets[index].balance = currentBalance;
        
        emit AssetRebalanced(token, currentBalance);
    }

    function updateSingleAssetWeight(address token, uint256 weight) internal validAsset(token) {
      uint256 id = assetIndex[token];
      Asset storage asset = assets[id];
      asset.targetWeight = weight;

    }
    function updateAllAssetWeights(address[] memory tokens, uint256[] memory weights) external onlyAgent{
      for (uint256 index = 0; index < tokens.length; index++) {
        updateSingleAssetWeight(tokens[index],weights[index]);
      }
      if (getTotalTargetWeight() != BASIS_POINTS) {
        revert InvalidWeight();
      }
    }
    
    // =============== ETF CORE FUNCTIONS ===============
    
    /**
     * @notice Deposit tokens into the ETF
     * @param token Token address
     * @param amount Amount to deposit
     * @return shares Amount of ETF shares minted
     */
    function deposit(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        validAsset(token) 
        returns (uint256 shares) 
    {
        require(amount >= MIN_DEPOSIT, "Amount too small");
        
        // Calculate shares to mint
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            shares = amount;
        } else {
            uint256 totalValue = getTotalValue();
            shares = (amount * totalSupply_) / totalValue;
        }
        
        // Transfer tokens to vault
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update asset balance
        uint256 index = assetIndex[token];
        assets[index].balance += amount;
        totalValueLocked += amount;
        
        // Mint shares
        _mint(msg.sender, shares);
    }
    
    /**
     * @notice Withdraw from ETF
     * @param shares Amount of shares to burn
     * @param tokenOut Token to receive
     * @param minAmountOut Minimum amount to receive
     * @return amountOut Amount received
     */
    function withdraw(uint256 shares, address tokenOut, uint256 minAmountOut) 
        external 
        nonReentrant 
        whenNotPaused 
        validAsset(tokenOut) 
        returns (uint256 amountOut) 
    {
        require(shares > 0, "Invalid shares");
        require(balanceOf(msg.sender) >= shares, "Insufficient shares");
        
        // Calculate withdrawal amount
        uint256 totalSupply_ = totalSupply();
        uint256 totalValue = getTotalValue();
        uint256 withdrawValue = (shares * totalValue) / totalSupply_;
        
        // Calculate token amount from asset balance
        uint256 index = assetIndex[tokenOut];
        uint256 assetBalance = assets[index].balance;
        amountOut = (withdrawValue * assetBalance) / totalValue;
        
        require(amountOut >= minAmountOut, "Slippage too high");
        require(assetBalance >= amountOut, "Insufficient asset balance");
        
        // Update state
        assets[index].balance -= amountOut;
        totalValueLocked -= withdrawValue;
        
        // Burn shares and transfer tokens
        _burn(msg.sender, shares);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
    
    // =============== LIQUIDITY MANAGEMENT ===============
    
    /**
     * @notice Move funds to external protocol (DeFi, bridge, etc.)
     * @param protocol Protocol address
     * @param token Token address
     * @param amount Amount to move
     * @param data Protocol-specific call data
     */
    function moveFundsToProtocol(
        address protocol,
        address token,
        uint256 amount,
        bytes calldata data
    ) external onlyAgent validAsset(token) nonReentrant {
        require(protocol != address(0), "Invalid protocol");
        
        uint256 index = assetIndex[token];
        require(assets[index].balance >= amount, "Insufficient asset balance");
        
        // Update asset balance
        assets[index].balance -= amount;
        
        // Approve and call protocol
        IERC20(token).forceApprove(protocol, amount);
        (bool success,) = protocol.call(data);
        require(success, "Protocol call failed");
        
        // Reset approval for security
        IERC20(token).forceApprove(protocol, 0);
        
        emit FundsMovedToProtocol(protocol, token, amount);
    }
    
    /**
     * @notice Retrieve funds from external protocol
     * @param protocol Protocol address
     * @param token Token address
     * @param expectedAmount Expected amount to retrieve
     * @param data Protocol-specific call data
     */
    function retrieveFundsFromProtocol(
        address protocol,
        address token,
        uint256 expectedAmount,
        bytes calldata data
    ) external onlyAgent validAsset(token) nonReentrant {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        
        // Call protocol to retrieve funds
        (bool success,) = protocol.call(data);
        require(success, "Protocol call failed");
        
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 retrieved = balanceAfter - balanceBefore;
        
        require(retrieved >= expectedAmount, "Insufficient retrieval");
        
        // Update asset balance
        uint256 index = assetIndex[token];
        assets[index].balance += retrieved;
        
        emit FundsRetrievedFromProtocol(protocol, token, retrieved);
    }
    
    // =============== CROSS-CHAIN MANAGEMENT ===============
    
    /**
     * @notice Add support for a cross-chain vault
     * @param chainId Target chain ID
     * @param vaultAddress Vault address on target chain
     */
    function addChainVault(uint256 chainId, address vaultAddress) external onlyAgent {
        require(chainId != block.chainid, "Cannot add current chain");
        require(vaultAddress != address(0), "Invalid vault");
        
        supportedChains[chainId] = true;
        chainVaults[chainId] = vaultAddress;
    }
    
    /**
     * @notice Transfer funds to cross-chain vault (simplified, no bridge integration)
     * @param chainId Target chain ID
     * @param token Token address
     * @param amount Amount to transfer
     * @dev In production, this would integrate with actual bridge protocols
     */
    function transferToChain(
        uint256 chainId,
        address token,
        uint256 amount
    ) external onlyAgent validAsset(token) {
        require(supportedChains[chainId], "Chain not supported");
        require(chainVaults[chainId] != address(0), "No vault on target chain");
        
        uint256 index = assetIndex[token];
        require(assets[index].balance >= amount, "Insufficient balance");
        
        // Update balance (funds are locked for cross-chain transfer)
        assets[index].balance -= amount;
        
        // In production, this would call bridge protocols
        // For now, we just emit an event
        emit CrossChainTransfer(chainId, token, amount);
    }
    
    // =============== VIEW FUNCTIONS ===============
    
    /**
     * @notice Get total value of all assets
     * @return totalValue Total value in token units
     */
    function getTotalValue() public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].active) {
                totalValue += assets[i].balance;
            }
        }
    }
    
    /**
     * @notice Get net asset value per share
     * @return nav NAV per share
     */
    function getNetAssetValue() external view returns (uint256 nav) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (getTotalValue() * 1e18) / supply;
    }
    
    /**
     * @notice Get total target weight of all active assets
     * @return totalWeight Total target weight in basis points
     */
    function getTotalTargetWeight() public view returns (uint256 totalWeight) {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].active) {
                totalWeight += assets[i].targetWeight;
            }
        }
    }
    
    /**
     * @notice Get all active assets
     * @return activeAssets Array of active asset addresses
     */
    function getActiveAssets() external view returns (address[] memory activeAssets) {
        uint256 activeCount = 0;
        
        // Count active assets
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].active) activeCount++;
        }
        
        // Build array
        activeAssets = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].active) {
                activeAssets[index] = assets[i].token;
                index++;
            }
        }
    }
    
    /**
     * @notice Get asset information
     * @param token Token address
     * @return asset Asset struct
     */
    function getAsset(address token) external view validAsset(token) returns (Asset memory asset) {
        return assets[assetIndex[token]];
    }
    
    // =============== EMERGENCY FUNCTIONS ===============
    
    /**
     * @notice Emergency pause
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Emergency token recovery
     * @param token Token to recover
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
    
    // =============== RECEIVE FUNCTION ===============
    
    receive() external payable {
        // Accept FLOW for gas and operations
    }
}
