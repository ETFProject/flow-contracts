// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FlowETFVault
 * @notice Advanced ETF Vault deployed on Flow EVM with agent wallet control and cross-chain capabilities
 * @dev Designed for Flow EVM (Chain ID: 545) with EIP-7702 delegation support
 *      Features: Agent wallet control, cross-chain fund management, batched operations
 */
contract FlowETFVault is ERC20, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============== CONSTANTS & CONFIGURATION ===============
    
    uint256 public constant FLOW_CHAIN_ID = 545;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_MANAGEMENT_FEE = 500; // 5% max
    uint256 public constant MAX_PERFORMANCE_FEE = 2000; // 20% max
    uint256 public constant MIN_DEPOSIT = 1e15; // 0.001 FLOW
    uint256 public constant REBALANCE_THRESHOLD = 500; // 5% deviation triggers rebalance
    
    // =============== STATE VARIABLES ===============
    
    // Agent Wallet Management
    address public agentWallet;
    mapping(address => bool) public authorizedAgents;
    uint256 public agentWalletNonce;
    
    // ETF Configuration
    struct AssetAllocation {
        address token;
        uint256 targetWeight; // In basis points
        uint256 currentWeight;
        bool isActive;
        uint256 lastRebalanceTime;
    }
    
    AssetAllocation[] public assetAllocations;
    mapping(address => uint256) public assetIndex; // token => index in assetAllocations
    mapping(address => bool) public supportedAssets;
    
    // Cross-chain Management
    mapping(uint256 => address) public chainVaults; // chainId => vault address
    mapping(uint256 => bool) public supportedChains;
    mapping(bytes32 => bool) public processedCrossChainTxs;
    
    struct CrossChainOperation {
        uint256 targetChainId;
        address targetVault;
        address asset;
        uint256 amount;
        bytes callData;
        uint256 timestamp;
        bool executed;
    }
    
    mapping(bytes32 => CrossChainOperation) public crossChainOperations;
    
    // Fee Management
    uint256 public managementFee = 200; // 2% annual
    uint256 public performanceFee = 1000; // 10% on profits
    uint256 public lastFeeCollection;
    uint256 public totalFeesCollected;
    
    // Performance Tracking
    uint256 public highWaterMark;
    uint256 public totalValueLocked;
    uint256 public lastRebalanceTime;
    uint256 public totalTrades;
    
    // EIP-7702 Integration
    mapping(address => bool) public isEIP7702Account;
    mapping(address => bytes32) public eip7702Nonces;
    
    // =============== EVENTS ===============
    
    event AgentWalletSet(address indexed oldAgent, address indexed newAgent);
    event AgentAuthorized(address indexed agent, bool authorized);
    event AssetAdded(address indexed token, uint256 targetWeight);
    event AssetRemoved(address indexed token);
    event AssetRebalanced(address indexed token, uint256 oldWeight, uint256 newWeight);
    event CrossChainTransfer(uint256 indexed targetChainId, address indexed asset, uint256 amount, bytes32 txHash);
    event CrossChainOperationExecuted(bytes32 indexed operationId, uint256 chainId, address asset, uint256 amount);
    event EIP7702BatchExecuted(address indexed eoa, uint256 callCount, uint256 gasUsed);
    event FeesCollected(uint256 managementFees, uint256 performanceFees);
    event Rebalanced(uint256 timestamp, uint256 totalValue);
    
    // =============== ERRORS ===============
    
    error Unauthorized();
    error InvalidAgent();
    error InvalidAsset();
    error InvalidAllocation();
    error InsufficientLiquidity();
    error CrossChainOperationFailed();
    error RebalanceThresholdNotMet();
    error InvalidChain();
    error OperationAlreadyExecuted();
    error EIP7702NotInitialized();
    
    // =============== MODIFIERS ===============
    
    modifier onlyAgent() {
        if (msg.sender != agentWallet && !authorizedAgents[msg.sender]) {
            revert Unauthorized();
        }
        _;
    }
    
    modifier onlyEIP7702() {
        if (!isEIP7702Account[msg.sender]) {
            revert EIP7702NotInitialized();
        }
        _;
    }
    
    modifier validAsset(address token) {
        if (!supportedAssets[token]) {
            revert InvalidAsset();
        }
        _;
    }
    
    // =============== CONSTRUCTOR ===============
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _agentWallet,
        address _initialOwner
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {
        if (_agentWallet == address(0)) revert InvalidAgent();
        
        agentWallet = _agentWallet;
        authorizedAgents[_agentWallet] = true;
        
        lastFeeCollection = block.timestamp;
        lastRebalanceTime = block.timestamp;
        highWaterMark = 1e18; // Start at 1.0
        
        // Initialize Flow EVM specific settings
        require(block.chainid == FLOW_CHAIN_ID, "Must deploy on Flow EVM");
        
        emit AgentWalletSet(address(0), _agentWallet);
    }
    
    // =============== AGENT WALLET MANAGEMENT ===============
    
    /**
     * @notice Set the primary agent wallet
     * @param _newAgent New agent wallet address
     */
    function setAgentWallet(address _newAgent) external onlyOwner {
        if (_newAgent == address(0)) revert InvalidAgent();
        
        address oldAgent = agentWallet;
        agentWallet = _newAgent;
        
        // Automatically authorize new agent
        authorizedAgents[_newAgent] = true;
        
        agentWalletNonce++;
        
        emit AgentWalletSet(oldAgent, _newAgent);
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
    
    // =============== EIP-7702 INTEGRATION ===============
    
    /**
     * @notice Register an EOA for EIP-7702 delegation
     * @param eoa EOA address that will delegate to this contract
     */
    function registerEIP7702Account(address eoa) external onlyAgent {
        isEIP7702Account[eoa] = true;
        eip7702Nonces[eoa] = keccak256(abi.encodePacked(eoa, block.timestamp));
    }
    
    /**
     * @notice Execute batched operations via EIP-7702 delegation
     * @param targets Array of target addresses to call
     * @param calldatas Array of calldata to send to each target
     * @param values Array of ETH values to send with each call
     * @dev This function is called by EOAs that have delegated to this contract
     */
    function executeBatchedOperations(
        address[] calldata targets,
        bytes[] calldata calldatas,
        uint256[] calldata values
    ) external onlyEIP7702 nonReentrant whenNotPaused returns (bytes[] memory results) {
        require(targets.length == calldatas.length && targets.length == values.length, "Array length mismatch");
        
        uint256 gasStart = gasleft();
        results = new bytes[](targets.length);
        
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, "Batched call failed");
            results[i] = result;
        }
        
        // Update nonce for replay protection
        eip7702Nonces[msg.sender] = keccak256(abi.encodePacked(eip7702Nonces[msg.sender], block.timestamp));
        
        uint256 gasUsed = gasStart - gasleft();
        emit EIP7702BatchExecuted(msg.sender, targets.length, gasUsed);
        
        return results;
    }
    
    /**
     * @notice Create batched calls for ETF operations
     * @param operations Array of operation types (0=deposit, 1=withdraw, 2=rebalance, 3=crossChain)
     * @param tokens Array of token addresses
     * @param amounts Array of amounts
     * @param extraData Additional data for complex operations
     */
    function createBatchedETFOperations(
        uint256[] calldata operations,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes[] calldata extraData
    ) external view onlyAgent returns (
        address[] memory targets,
        bytes[] memory calldatas,
        uint256[] memory values
    ) {
        uint256 opsLength = operations.length;
        require(opsLength == tokens.length && opsLength == amounts.length, "Array length mismatch");
        
        targets = new address[](opsLength);
        calldatas = new bytes[](opsLength);
        values = new uint256[](opsLength);
        
        for (uint256 i = 0; i < opsLength; i++) {
            targets[i] = address(this);
            values[i] = 0;
            
            if (operations[i] == 0) { // Deposit
                calldatas[i] = abi.encodeWithSignature("deposit(address,uint256)", tokens[i], amounts[i]);
            } else if (operations[i] == 1) { // Withdraw
                calldatas[i] = abi.encodeWithSignature("withdraw(uint256,address,uint256)", amounts[i], tokens[i], 0);
            } else if (operations[i] == 2) { // Rebalance
                calldatas[i] = abi.encodeWithSignature("rebalanceAsset(address)", tokens[i]);
            } else if (operations[i] == 3) { // Cross-chain transfer
                (uint256 chainId, address targetVault) = abi.decode(extraData[i], (uint256, address));
                calldatas[i] = abi.encodeWithSignature(
                    "initiateCrossChainTransfer(uint256,address,address,uint256)", 
                    chainId, targetVault, tokens[i], amounts[i]
                );
            }
        }
        
        return (targets, calldatas, values);
    }
    
    // =============== ETF CORE FUNCTIONALITY ===============
    
    /**
     * @notice Deposit assets into the ETF
     * @param token Token address to deposit
     * @param amount Amount to deposit
     */
    function deposit(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        validAsset(token) 
        returns (uint256 shares) 
    {
        require(amount >= MIN_DEPOSIT, "Amount below minimum");
        
        // Calculate shares to mint
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            shares = amount;
        } else {
            uint256 totalValue = getTotalValue();
            shares = (amount * totalSupply_) / totalValue;
        }
        
        // Transfer tokens from user
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Mint ETF shares
        _mint(msg.sender, shares);
        
        // Update TVL
        totalValueLocked += amount;
        
        // Trigger rebalance if needed
        _checkAndTriggerRebalance();
        
        emit Transfer(address(0), msg.sender, shares);
    }
    
    /**
     * @notice Withdraw assets from the ETF
     * @param shares Amount of ETF shares to burn
     * @param tokenOut Token to receive
     * @param minAmountOut Minimum amount to receive
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
        
        // Calculate token amount based on current allocation
        uint256 tokenBalance = IERC20(tokenOut).balanceOf(address(this));
        amountOut = (withdrawValue * tokenBalance) / getTotalValue();
        
        require(amountOut >= minAmountOut, "Slippage too high");
        require(tokenBalance >= amountOut, "Insufficient liquidity");
        
        // Burn shares
        _burn(msg.sender, shares);
        
        // Transfer tokens to user
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        
        // Update TVL
        totalValueLocked -= withdrawValue;
        
        emit Transfer(msg.sender, address(0), shares);
    }
    
    // =============== ASSET MANAGEMENT ===============
    
    /**
     * @notice Add a new asset to the ETF with target allocation
     * @param token Token address
     * @param targetWeight Target weight in basis points
     */
    function addAsset(address token, uint256 targetWeight) external onlyAgent {
        require(token != address(0), "Invalid token");
        require(!supportedAssets[token], "Asset already added");
        require(targetWeight <= BASIS_POINTS, "Invalid weight");
        
        // Ensure total weights don't exceed 100%
        uint256 totalWeight = getTotalTargetWeight();
        require(totalWeight + targetWeight <= BASIS_POINTS, "Total weight exceeds 100%");
        
        assetAllocations.push(AssetAllocation({
            token: token,
            targetWeight: targetWeight,
            currentWeight: 0,
            isActive: true,
            lastRebalanceTime: block.timestamp
        }));
        
        assetIndex[token] = assetAllocations.length - 1;
        supportedAssets[token] = true;
        
        emit AssetAdded(token, targetWeight);
    }
    
    /**
     * @notice Remove an asset from the ETF
     * @param token Token address to remove
     */
    function removeAsset(address token) external onlyAgent validAsset(token) {
        uint256 index = assetIndex[token];
        assetAllocations[index].isActive = false;
        supportedAssets[token] = false;
        
        emit AssetRemoved(token);
    }
    
    /**
     * @notice Rebalance a specific asset to its target weight
     * @param token Token to rebalance
     */
    function rebalanceAsset(address token) external onlyAgent validAsset(token) {
        uint256 index = assetIndex[token];
        AssetAllocation storage allocation = assetAllocations[index];
        
        require(allocation.isActive, "Asset not active");
        
        uint256 currentValue = IERC20(token).balanceOf(address(this));
        uint256 totalValue = getTotalValue();
        uint256 currentWeight = totalValue > 0 ? (currentValue * BASIS_POINTS) / totalValue : 0;
        
        uint256 weightDiff = currentWeight > allocation.targetWeight 
            ? currentWeight - allocation.targetWeight 
            : allocation.targetWeight - currentWeight;
            
        require(weightDiff >= REBALANCE_THRESHOLD, "Rebalance threshold not met");
        
        allocation.currentWeight = currentWeight;
        allocation.lastRebalanceTime = block.timestamp;
        lastRebalanceTime = block.timestamp;
        totalTrades++;
        
        emit AssetRebalanced(token, currentWeight, allocation.targetWeight);
    }
    
    // =============== CROSS-CHAIN OPERATIONS ===============
    
    /**
     * @notice Add support for a new chain
     * @param chainId Chain ID to support
     * @param vaultAddress Vault address on the target chain
     */
    function addSupportedChain(uint256 chainId, address vaultAddress) external onlyAgent {
        require(chainId != block.chainid, "Cannot add current chain");
        require(vaultAddress != address(0), "Invalid vault address");
        
        supportedChains[chainId] = true;
        chainVaults[chainId] = vaultAddress;
    }
    
    /**
     * @notice Initiate cross-chain transfer of assets
     * @param targetChainId Target chain ID
     * @param targetVault Target vault address
     * @param asset Asset to transfer
     * @param amount Amount to transfer
     */
    function initiateCrossChainTransfer(
        uint256 targetChainId,
        address targetVault,
        address asset,
        uint256 amount
    ) external onlyAgent validAsset(asset) returns (bytes32 operationId) {
        require(supportedChains[targetChainId], "Chain not supported");
        require(chainVaults[targetChainId] == targetVault, "Invalid target vault");
        require(IERC20(asset).balanceOf(address(this)) >= amount, "Insufficient balance");
        
        operationId = keccak256(abi.encodePacked(
            targetChainId,
            targetVault,
            asset,
            amount,
            block.timestamp,
            agentWalletNonce++
        ));
        
        crossChainOperations[operationId] = CrossChainOperation({
            targetChainId: targetChainId,
            targetVault: targetVault,
            asset: asset,
            amount: amount,
            callData: abi.encodeWithSignature("deposit(address,uint256)", asset, amount),
            timestamp: block.timestamp,
            executed: false
        });
        
        // Lock the assets (in production, this would interact with a bridge)
        IERC20(asset).safeTransfer(address(this), amount);
        
        emit CrossChainTransfer(targetChainId, asset, amount, operationId);
        return operationId;
    }
    
    /**
     * @notice Execute cross-chain operation (called by bridge/agent)
     * @param operationId Operation ID to execute
     */
    function executeCrossChainOperation(bytes32 operationId) external onlyAgent {
        CrossChainOperation storage operation = crossChainOperations[operationId];
        require(!operation.executed, "Operation already executed");
        require(operation.timestamp > 0, "Operation not found");
        
        operation.executed = true;
        
        // In production, this would interact with LayerZero, Connext, or other bridges
        // For now, we simulate the cross-chain call
        
        emit CrossChainOperationExecuted(
            operationId,
            operation.targetChainId,
            operation.asset,
            operation.amount
        );
    }
    
    // =============== LIQUIDITY MANAGEMENT ===============
    
    /**
     * @notice Move liquidity to external protocols (DeFi, other chains)
     * @param protocol Protocol address or identifier
     * @param asset Asset to move
     * @param amount Amount to move
     * @param data Additional data for the protocol interaction
     */
    function moveLiquidityToProtocol(
        address protocol,
        address asset,
        uint256 amount,
        bytes calldata data
    ) external onlyAgent validAsset(asset) nonReentrant {
        require(protocol != address(0), "Invalid protocol");
        require(IERC20(asset).balanceOf(address(this)) >= amount, "Insufficient balance");
        
        // Approve protocol to spend tokens
        IERC20(asset).forceApprove(protocol, amount);
        
        // Execute protocol interaction
        (bool success,) = protocol.call(data);
        require(success, "Protocol interaction failed");
        
        // Reset approval for security
        IERC20(asset).forceApprove(protocol, 0);
        
        totalTrades++;
    }
    
    /**
     * @notice Retrieve liquidity from external protocols
     * @param protocol Protocol address
     * @param asset Asset to retrieve
     * @param amount Amount to retrieve
     * @param data Additional data for withdrawal
     */
    function retrieveLiquidityFromProtocol(
        address protocol,
        address asset,
        uint256 amount,
        bytes calldata data
    ) external onlyAgent validAsset(asset) nonReentrant {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        
        // Execute withdrawal from protocol
        (bool success,) = protocol.call(data);
        require(success, "Protocol withdrawal failed");
        
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        require(balanceAfter >= balanceBefore + amount, "Insufficient withdrawal");
        
        totalTrades++;
    }
    
    // =============== FEE MANAGEMENT ===============
    
    /**
     * @notice Collect management and performance fees
     */
    function collectFees() external onlyAgent {
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - lastFeeCollection;
        
        if (timeElapsed == 0) return;
        
        uint256 totalValue = getTotalValue();
        uint256 currentNAV = totalSupply() > 0 ? (totalValue * 1e18) / totalSupply() : 1e18;
        
        // Management fees (annual)
        uint256 managementFees = (totalValue * managementFee * timeElapsed) / (BASIS_POINTS * 365 days);
        
        // Performance fees (only on new high water mark)
        uint256 performanceFees = 0;
        if (currentNAV > highWaterMark) {
            uint256 profit = (currentNAV - highWaterMark) * totalSupply() / 1e18;
            performanceFees = (profit * performanceFee) / BASIS_POINTS;
            highWaterMark = currentNAV;
        }
        
        uint256 totalFees = managementFees + performanceFees;
        if (totalFees > 0) {
            // Mint fee shares to agent wallet
            uint256 feeShares = totalSupply() > 0 ? (totalFees * totalSupply()) / (totalValue - totalFees) : totalFees;
            _mint(agentWallet, feeShares);
            
            totalFeesCollected += totalFees;
        }
        
        lastFeeCollection = currentTime;
        
        emit FeesCollected(managementFees, performanceFees);
    }
    
    // =============== VIEW FUNCTIONS ===============
    
    /**
     * @notice Get total value of all assets in the vault
     */
    function getTotalValue() public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < assetAllocations.length; i++) {
            if (assetAllocations[i].isActive) {
                uint256 balance = IERC20(assetAllocations[i].token).balanceOf(address(this));
                totalValue += balance; // In production, would convert to common denomination
            }
        }
        return totalValue;
    }
    
    /**
     * @notice Get current net asset value per share
     */
    function getNetAssetValue() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (getTotalValue() * 1e18) / supply;
    }
    
    /**
     * @notice Get total target weight of all assets
     */
    function getTotalTargetWeight() public view returns (uint256 totalWeight) {
        for (uint256 i = 0; i < assetAllocations.length; i++) {
            if (assetAllocations[i].isActive) {
                totalWeight += assetAllocations[i].targetWeight;
            }
        }
        return totalWeight;
    }
    
    /**
     * @notice Get asset allocation info
     */
    function getAssetAllocation(address token) external view validAsset(token) returns (AssetAllocation memory) {
        return assetAllocations[assetIndex[token]];
    }
    
    /**
     * @notice Get all active assets
     */
    function getActiveAssets() external view returns (address[] memory activeAssets) {
        uint256 activeCount = 0;
        
        // Count active assets
        for (uint256 i = 0; i < assetAllocations.length; i++) {
            if (assetAllocations[i].isActive) {
                activeCount++;
            }
        }
        
        // Create array of active assets
        activeAssets = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < assetAllocations.length; i++) {
            if (assetAllocations[i].isActive) {
                activeAssets[index] = assetAllocations[i].token;
                index++;
            }
        }
        
        return activeAssets;
    }
    
    /**
     * @notice Check if rebalancing is needed
     */
    function needsRebalancing() external view returns (bool) {
        uint256 totalValue = getTotalValue();
        if (totalValue == 0) return false;
        
        for (uint256 i = 0; i < assetAllocations.length; i++) {
            if (assetAllocations[i].isActive) {
                uint256 currentValue = IERC20(assetAllocations[i].token).balanceOf(address(this));
                uint256 currentWeight = (currentValue * BASIS_POINTS) / totalValue;
                uint256 weightDiff = currentWeight > assetAllocations[i].targetWeight 
                    ? currentWeight - assetAllocations[i].targetWeight 
                    : assetAllocations[i].targetWeight - currentWeight;
                    
                if (weightDiff >= REBALANCE_THRESHOLD) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    // =============== INTERNAL FUNCTIONS ===============
    
    /**
     * @notice Check if rebalancing is needed and trigger if necessary
     */
    function _checkAndTriggerRebalance() internal {
        if (this.needsRebalancing()) {
            lastRebalanceTime = block.timestamp;
            emit Rebalanced(block.timestamp, getTotalValue());
        }
    }
    
    // =============== EMERGENCY FUNCTIONS ===============
    
    /**
     * @notice Emergency pause (owner only)
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Emergency unpause (owner only)
     */
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Emergency withdrawal (owner only)
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
    
    // =============== RECEIVE FUNCTIONS ===============
    
    receive() external payable {
        // Accept FLOW for gas and operations
    }
    
    fallback() external payable {
        // Handle other calls
    }
}
