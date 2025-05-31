// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../crosschain/LayerZeroVault.sol";

/**
 * @title FlowEIP7702ETFImplementation
 * @notice EIP-7702 implementation for Flow EVM with enhanced cross-chain capabilities
 * @dev Designed specifically for Flow EVM (Chain ID: 545) with agent wallet integration
 *      Provides advanced batching, cross-chain operations, and DeFi integrations
 */
contract FlowEIP7702ETFImplementation is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =============== CONSTANTS ===============
    
    uint256 public constant FLOW_CHAIN_ID = 545;
    uint256 public constant MAX_BATCH_SIZE = 20;
    uint256 public constant MIN_GAS_LIMIT = 50000;
    
    // =============== STORAGE SLOTS ===============
    
    // Using Flow-specific slot names to avoid collisions
    bytes32 private constant FLOW_NONCE_SLOT = keccak256("flow.eip7702.etf.nonce");
    bytes32 private constant FLOW_INITIALIZED_SLOT = keccak256("flow.eip7702.etf.initialized");
    bytes32 private constant FLOW_VAULT_SLOT = keccak256("flow.eip7702.etf.vault");
    bytes32 private constant FLOW_AGENT_SLOT = keccak256("flow.eip7702.etf.agent");
    bytes32 private constant FLOW_OWNER_SLOT = keccak256("flow.eip7702.etf.owner");
    bytes32 private constant FLOW_CHAIN_VAULTS_SLOT = keccak256("flow.eip7702.etf.chainvaults");
    
    // =============== STRUCTURES ===============
    
    struct FlowBatchCall {
        address target;
        bytes data;
        uint256 value;
        uint256 gasLimit;
        bool requireSuccess;
    }
    
    struct CrossChainSwap {
        uint256 sourceChainId;
        uint256 targetChainId;
        address sourceToken;
        address targetToken;
        uint256 amountIn;
        uint256 minAmountOut;
        address targetVault;
        bytes bridgeData;
    }
    
    struct DeFiOperation {
        address protocol;
        address inputToken;
        address outputToken;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes operationData;
        uint256 deadline;
    }
    
    // =============== EVENTS ===============
    
    event FlowEIP7702Initialized(address indexed eoa, address indexed vault, address indexed agent);
    event FlowBatchExecuted(address indexed eoa, uint256 callCount, uint256 gasUsed, uint256 successCount);
    event CrossChainSwapInitiated(address indexed eoa, uint256 sourceChain, uint256 targetChain, address token, uint256 amount);
    event DeFiOperationExecuted(address indexed eoa, address protocol, address inputToken, address outputToken, uint256 amountIn, uint256 amountOut);
    event LiquidityMoved(address indexed eoa, address indexed protocol, address token, uint256 amount, string operation);
    event FlowAgentSet(address indexed eoa, address indexed oldAgent, address indexed newAgent);
    
    // =============== ERRORS ===============
    
    error FlowNotInitialized();
    error FlowAlreadyInitialized();
    error FlowUnauthorized();
    error FlowInvalidVault();
    error FlowInvalidAgent();
    error FlowInvalidChain();
    error FlowCallFailed(uint256 index, bytes reason);
    error FlowInsufficientBalance();
    error FlowExceedsMaxBatch();
    error FlowDeadlineExceeded();
    error FlowSlippageExceeded();
    
    // =============== MODIFIERS ===============
    
    modifier onlyFlowInitialized() {
        if (!_isFlowInitialized()) revert FlowNotInitialized();
        _;
    }
    
    modifier onlyFlowAgent() {
        if (msg.sender != _getFlowAgent()) revert FlowUnauthorized();
        _;
    }
    
    modifier validFlowChain() {
        require(block.chainid == FLOW_CHAIN_ID, "Must be on Flow EVM");
        _;
    }
    
    // =============== INITIALIZATION ===============
    
    /**
     * @notice Initialize Flow EIP-7702 delegation for advanced ETF operations
     * @param _vault Flow ETF vault address
     * @param _agent Agent wallet address with fund control
     */
    function initializeFlowETF(address _vault, address _agent) external validFlowChain {
        if (_isFlowInitialized()) revert FlowAlreadyInitialized();
        if (_vault == address(0)) revert FlowInvalidVault();
        if (_agent == address(0)) revert FlowInvalidAgent();
        
        address eoa = address(this); // The delegating EOA
        
        _setFlowInitialized(true);
        _setFlowVault(_vault);
        _setFlowAgent(_agent);
        _setFlowOwner(eoa);
        _setFlowNonce(1);
        
        // Register this EOA with the vault for enhanced permissions
        (bool success,) = _vault.call(
            abi.encodeWithSignature("registerEIP7702Account(address)", eoa)
        );
        require(success, "Vault registration failed");
        
        emit FlowEIP7702Initialized(eoa, _vault, _agent);
    }
    
    // =============== ADVANCED BATCHING OPERATIONS ===============
    
    /**
     * @notice Execute sophisticated batch operations on Flow EVM
     * @param calls Array of calls with individual gas limits and success requirements
     * @return results Array of call results
     * @return successCount Number of successful calls
     */
    function executeFlowBatch(FlowBatchCall[] calldata calls) 
        external 
        onlyFlowInitialized 
        nonReentrant 
        returns (bytes[] memory results, uint256 successCount) 
    {
        if (calls.length > MAX_BATCH_SIZE) revert FlowExceedsMaxBatch();
        
        uint256 gasStart = gasleft();
        results = new bytes[](calls.length);
        successCount = 0;
        
        for (uint256 i = 0; i < calls.length; i++) {
            FlowBatchCall memory call = calls[i];
            
            // Ensure minimum gas for call
            if (gasleft() < call.gasLimit + MIN_GAS_LIMIT) {
                if (call.requireSuccess) {
                    revert FlowCallFailed(i, "Insufficient gas");
                }
                continue;
            }
            
            (bool success, bytes memory result) = call.target.call{
                value: call.value,
                gas: call.gasLimit
            }(call.data);
            
            if (success) {
                successCount++;
                results[i] = result;
            } else if (call.requireSuccess) {
                revert FlowCallFailed(i, result);
            }
        }
        
        // Update nonce for replay protection
        uint256 currentNonce = _getFlowNonce();
        _setFlowNonce(currentNonce + 1);
        
        uint256 gasUsed = gasStart - gasleft();
        emit FlowBatchExecuted(address(this), calls.length, gasUsed, successCount);
        
        return (results, successCount);
    }
    
    /**
     * @notice Create optimized batch calls for common Flow ETF operations
     * @param operations Array of operation types
     * @param tokens Array of token addresses
     * @param amounts Array of amounts
     * @param recipients Array of recipient addresses (for transfers)
     * @param extraData Additional data for complex operations
     */
    function createFlowETFBatch(
        uint256[] calldata operations,
        address[] calldata tokens,
        uint256[] calldata amounts,
        address[] calldata recipients,
        bytes[] calldata extraData
    ) external view onlyFlowInitialized returns (FlowBatchCall[] memory calls) {
        uint256 opsLength = operations.length;
        require(opsLength <= MAX_BATCH_SIZE, "Exceeds max batch size");
        
        calls = new FlowBatchCall[](opsLength);
        address vault = _getFlowVault();
        
        for (uint256 i = 0; i < opsLength; i++) {
            if (operations[i] == 0) { // ETF Deposit
                calls[i] = FlowBatchCall({
                    target: vault,
                    data: abi.encodeWithSignature("deposit(address,uint256)", tokens[i], amounts[i]),
                    value: 0,
                    gasLimit: 150000,
                    requireSuccess: true
                });
                
            } else if (operations[i] == 1) { // ETF Withdraw
                calls[i] = FlowBatchCall({
                    target: vault,
                    data: abi.encodeWithSignature("withdraw(uint256,address,uint256)", amounts[i], tokens[i], 0),
                    value: 0,
                    gasLimit: 200000,
                    requireSuccess: true
                });
                
            } else if (operations[i] == 2) { // Token Transfer
                calls[i] = FlowBatchCall({
                    target: tokens[i],
                    data: abi.encodeWithSignature("transfer(address,uint256)", recipients[i], amounts[i]),
                    value: 0,
                    gasLimit: 100000,
                    requireSuccess: true
                });
                
            } else if (operations[i] == 3) { // Token Approval
                calls[i] = FlowBatchCall({
                    target: tokens[i],
                    data: abi.encodeWithSignature("approve(address,uint256)", recipients[i], amounts[i]),
                    value: 0,
                    gasLimit: 80000,
                    requireSuccess: true
                });
                
            } else if (operations[i] == 4) { // Cross-chain Transfer
                (uint256 targetChainId, address targetVault) = abi.decode(extraData[i], (uint256, address));
                calls[i] = FlowBatchCall({
                    target: vault,
                    data: abi.encodeWithSignature(
                        "initiateCrossChainTransfer(uint256,address,address,uint256)",
                        targetChainId, targetVault, tokens[i], amounts[i]
                    ),
                    value: 0,
                    gasLimit: 300000,
                    requireSuccess: true
                });
                
            } else if (operations[i] == 5) { // DeFi Protocol Interaction
                (address protocol, bytes memory protocolData) = abi.decode(extraData[i], (address, bytes));
                calls[i] = FlowBatchCall({
                    target: protocol,
                    data: protocolData,
                    value: 0,
                    gasLimit: 400000,
                    requireSuccess: false // DeFi calls can be risky
                });
            }
        }
        
        return calls;
    }
    
    // =============== CROSS-CHAIN OPERATIONS ===============
    
    /**
     * @notice Execute cross-chain swap with optimal routing
     * @param swap Cross-chain swap parameters
     */
    function executeFlowCrossChainSwap(CrossChainSwap calldata swap) 
        external 
        onlyFlowInitialized 
        nonReentrant 
        returns (bytes32 swapId) 
    {
        require(swap.sourceChainId == FLOW_CHAIN_ID, "Must originate from Flow");
        require(swap.amountIn > 0, "Invalid amount");
        
        address eoa = address(this);
        
        // Check balance
        if (IERC20(swap.sourceToken).balanceOf(eoa) < swap.amountIn) {
            revert FlowInsufficientBalance();
        }
        
        // Generate unique swap ID
        swapId = keccak256(abi.encodePacked(
            swap.sourceChainId,
            swap.targetChainId,
            swap.sourceToken,
            swap.targetToken,
            swap.amountIn,
            block.timestamp,
            _getFlowNonce()
        ));
        
        // If target chain has LayerZero vault, use direct integration
        if (swap.targetChainId == 84532 || swap.targetChainId == 421614 || swap.targetChainId == 11155420) { // Base, Arbitrum, Optimism
            _executeLayerZeroSwap(swap, swapId);
        } else {
            // Use bridge data for other chains
            _executeBridgeSwap(swap, swapId);
        }
        
        // Update nonce
        uint256 currentNonce = _getFlowNonce();
        _setFlowNonce(currentNonce + 1);
        
        emit CrossChainSwapInitiated(eoa, swap.sourceChainId, swap.targetChainId, swap.sourceToken, swap.amountIn);
        return swapId;
    }
    
    /**
     * @notice Execute LayerZero-based cross-chain swap
     */
    function _executeLayerZeroSwap(CrossChainSwap memory swap, bytes32 swapId) internal {
        address vault = _getFlowVault();
        
        // Call the vault's LayerZero integration
        (bool success,) = vault.call(
            abi.encodeWithSignature(
                "initiateCrossChainTransfer(uint256,address,address,uint256)",
                swap.targetChainId,
                swap.targetVault,
                swap.sourceToken,
                swap.amountIn
            )
        );
        
        require(success, "LayerZero swap failed");
    }
    
    /**
     * @notice Execute bridge-based cross-chain swap
     */
    function _executeBridgeSwap(CrossChainSwap memory swap, bytes32 swapId) internal {
        // Implementation for other bridge protocols
        // This would integrate with Connext, Hop, or other bridges
        
        // For now, we simulate the operation
        address eoa = address(this);
        IERC20(swap.sourceToken).safeTransfer(address(this), swap.amountIn);
    }
    
    // =============== DEFI INTEGRATIONS ===============
    
    /**
     * @notice Execute DeFi operation (yield farming, swapping, lending)
     * @param operation DeFi operation parameters
     */
    function executeFlowDeFiOperation(DeFiOperation calldata operation) 
        external 
        onlyFlowInitialized 
        nonReentrant 
        returns (uint256 amountOut) 
    {
        if (block.timestamp > operation.deadline) revert FlowDeadlineExceeded();
        
        address eoa = address(this);
        
        // Check input balance
        uint256 inputBalance = IERC20(operation.inputToken).balanceOf(eoa);
        if (inputBalance < operation.amountIn) revert FlowInsufficientBalance();
        
        // Record output token balance before operation
        uint256 outputBalanceBefore = IERC20(operation.outputToken).balanceOf(eoa);
        
        // Approve protocol to spend input tokens
        IERC20(operation.inputToken).forceApprove(operation.protocol, operation.amountIn);
        
        // Execute DeFi operation
        (bool success,) = operation.protocol.call(operation.operationData);
        
        if (!success) {
            // Reset approval on failure
            IERC20(operation.inputToken).forceApprove(operation.protocol, 0);
            revert FlowCallFailed(0, "DeFi operation failed");
        }
        
        // Calculate received amount
        uint256 outputBalanceAfter = IERC20(operation.outputToken).balanceOf(eoa);
        amountOut = outputBalanceAfter - outputBalanceBefore;
        
        // Check slippage
        if (amountOut < operation.minAmountOut) revert FlowSlippageExceeded();
        
        // Reset approval for security
        IERC20(operation.inputToken).forceApprove(operation.protocol, 0);
        
        // Update nonce
        uint256 currentNonce = _getFlowNonce();
        _setFlowNonce(currentNonce + 1);
        
        emit DeFiOperationExecuted(eoa, operation.protocol, operation.inputToken, operation.outputToken, operation.amountIn, amountOut);
        return amountOut;
    }
    
    // =============== LIQUIDITY MANAGEMENT ===============
    
    /**
     * @notice Move liquidity to external protocol for yield generation
     * @param protocol Target protocol address
     * @param token Token to move
     * @param amount Amount to move
     * @param operationData Protocol-specific call data
     */
    function moveFlowLiquidityOut(
        address protocol,
        address token,
        uint256 amount,
        bytes calldata operationData
    ) external onlyFlowInitialized nonReentrant {
        require(protocol != address(0), "Invalid protocol");
        
        address eoa = address(this);
        
        // Check balance
        if (IERC20(token).balanceOf(eoa) < amount) revert FlowInsufficientBalance();
        
        // Approve and execute
        IERC20(token).forceApprove(protocol, amount);
        
        (bool success,) = protocol.call(operationData);
        require(success, "Liquidity move failed");
        
        // Reset approval
        IERC20(token).forceApprove(protocol, 0);
        
        emit LiquidityMoved(eoa, protocol, token, amount, "OUT");
    }
    
    /**
     * @notice Retrieve liquidity from external protocol
     * @param protocol Source protocol address
     * @param token Token to retrieve
     * @param amount Expected amount to retrieve
     * @param operationData Protocol-specific call data
     */
    function retrieveFlowLiquidity(
        address protocol,
        address token,
        uint256 amount,
        bytes calldata operationData
    ) external onlyFlowInitialized nonReentrant {
        address eoa = address(this);
        uint256 balanceBefore = IERC20(token).balanceOf(eoa);
        
        // Execute withdrawal
        (bool success,) = protocol.call(operationData);
        require(success, "Liquidity retrieval failed");
        
        uint256 balanceAfter = IERC20(token).balanceOf(eoa);
        uint256 retrieved = balanceAfter - balanceBefore;
        
        require(retrieved >= amount, "Insufficient retrieval");
        
        emit LiquidityMoved(eoa, protocol, token, retrieved, "IN");
    }
    
    // =============== AGENT MANAGEMENT ===============
    
    /**
     * @notice Update agent wallet (only current agent)
     * @param newAgent New agent wallet address
     */
    function setFlowAgent(address newAgent) external onlyFlowInitialized onlyFlowAgent {
        if (newAgent == address(0)) revert FlowInvalidAgent();
        
        address oldAgent = _getFlowAgent();
        _setFlowAgent(newAgent);
        
        emit FlowAgentSet(address(this), oldAgent, newAgent);
    }
    
    /**
     * @notice Add cross-chain vault for agent operations
     * @param chainId Target chain ID
     * @param vaultAddress Vault address on target chain
     */
    function addFlowChainVault(uint256 chainId, address vaultAddress) external onlyFlowInitialized onlyFlowAgent {
        require(chainId != FLOW_CHAIN_ID, "Cannot add Flow chain");
        require(vaultAddress != address(0), "Invalid vault");
        
        bytes32 slot = keccak256(abi.encodePacked(FLOW_CHAIN_VAULTS_SLOT, chainId));
        assembly {
            sstore(slot, vaultAddress)
        }
    }
    
    // =============== VIEW FUNCTIONS ===============
    
    function isFlowInitialized() external view returns (bool) {
        return _isFlowInitialized();
    }
    
    function getFlowVault() external view returns (address) {
        return _getFlowVault();
    }
    
    function getFlowAgent() external view returns (address) {
        return _getFlowAgent();
    }
    
    function getFlowOwner() external view returns (address) {
        return _getFlowOwner();
    }
    
    function getFlowNonce() external view returns (uint256) {
        return _getFlowNonce();
    }
    
    function getFlowChainVault(uint256 chainId) external view returns (address) {
        bytes32 slot = keccak256(abi.encodePacked(FLOW_CHAIN_VAULTS_SLOT, chainId));
        address vault;
        assembly {
            vault := sload(slot)
        }
        return vault;
    }
    
    // =============== INTERNAL STORAGE FUNCTIONS ===============
    
    function _isFlowInitialized() internal view returns (bool) {
        bytes32 slot = FLOW_INITIALIZED_SLOT;
        bool initialized;
        assembly {
            initialized := sload(slot)
        }
        return initialized;
    }
    
    function _setFlowInitialized(bool _initialized) internal {
        bytes32 slot = FLOW_INITIALIZED_SLOT;
        assembly {
            sstore(slot, _initialized)
        }
    }
    
    function _getFlowVault() internal view returns (address) {
        bytes32 slot = FLOW_VAULT_SLOT;
        address vault;
        assembly {
            vault := sload(slot)
        }
        return vault;
    }
    
    function _setFlowVault(address _vault) internal {
        bytes32 slot = FLOW_VAULT_SLOT;
        assembly {
            sstore(slot, _vault)
        }
    }
    
    function _getFlowAgent() internal view returns (address) {
        bytes32 slot = FLOW_AGENT_SLOT;
        address agent;
        assembly {
            agent := sload(slot)
        }
        return agent;
    }
    
    function _setFlowAgent(address _agent) internal {
        bytes32 slot = FLOW_AGENT_SLOT;
        assembly {
            sstore(slot, _agent)
        }
    }
    
    function _getFlowOwner() internal view returns (address) {
        bytes32 slot = FLOW_OWNER_SLOT;
        address owner;
        assembly {
            owner := sload(slot)
        }
        return owner;
    }
    
    function _setFlowOwner(address _owner) internal {
        bytes32 slot = FLOW_OWNER_SLOT;
        assembly {
            sstore(slot, _owner)
        }
    }
    
    function _getFlowNonce() internal view returns (uint256) {
        bytes32 slot = FLOW_NONCE_SLOT;
        uint256 nonce;
        assembly {
            nonce := sload(slot)
        }
        return nonce;
    }
    
    function _setFlowNonce(uint256 _nonce) internal {
        bytes32 slot = FLOW_NONCE_SLOT;
        assembly {
            sstore(slot, _nonce)
        }
    }
    
    // =============== EMERGENCY FUNCTIONS ===============
    
    /**
     * @notice Emergency function to revoke delegation and clear state
     */
    function revokeFlowDelegation() external onlyFlowInitialized {
        // Clear all storage
        _setFlowInitialized(false);
        _setFlowVault(address(0));
        _setFlowAgent(address(0));
        _setFlowOwner(address(0));
        _setFlowNonce(0);
        
        // Note: Actual delegation revocation happens at protocol level
    }
    
    // Allow receiving FLOW
    receive() external payable {}
}
