// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title FlowEIP7702Implementation
 * @notice Simple, focused EIP-7702 implementation for Flow ETF operations
 * @dev Designed for Flow EVM (Chain ID: 545) following EIP-7702 best practices
 *      Keeps implementation minimal and auditable as recommended
 */
contract FlowEIP7702Implementation {
    
    // =============== CONSTANTS ===============
    
    uint256 public constant FLOW_CHAIN_ID = 545;
    
    // =============== STORAGE ===============
    
    // Use deterministic slots to avoid collisions with EOA state
    bytes32 private constant NONCE_SLOT = keccak256("flow.eip7702.nonce");
    bytes32 private constant VAULT_SLOT = keccak256("flow.eip7702.vault");
    bytes32 private constant AGENT_SLOT = keccak256("flow.eip7702.agent");
    
    // =============== EVENTS ===============
    
    event BatchExecuted(address indexed eoa, uint256 callCount, uint256 successCount);
    event VaultSet(address indexed eoa, address indexed vault);
    event AgentSet(address indexed eoa, address indexed agent);
    
    // =============== ERRORS ===============
    
    error UnauthorizedAgent();
    error InvalidVault();
    error InvalidAgent();
    error CallFailed(uint256 index);
    error InvalidChain();
    
    // =============== MODIFIERS ===============
    
    modifier onlyValidChain() {
        if (block.chainid != FLOW_CHAIN_ID) revert InvalidChain();
        _;
    }
    
    modifier onlyAgent() {
        if (msg.sender != _getAgent()) revert UnauthorizedAgent();
        _;
    }
    
    // =============== INITIALIZATION ===============
    
    /**
     * @notice Initialize the ETF delegation for this EOA
     * @param vault The ETF vault address
     * @param agent The authorized agent wallet
     */
    function initialize(address vault, address agent) external onlyValidChain {
        if (vault == address(0)) revert InvalidVault();
        if (agent == address(0)) revert InvalidAgent();
        
        _setVault(vault);
        _setAgent(agent);
        _setNonce(1);
        
        emit VaultSet(address(this), vault);
        emit AgentSet(address(this), agent);
    }
    
    // =============== BATCH OPERATIONS ===============
    
    /**
     * @notice Execute batch of calls as delegated EOA
     * @param targets Array of target addresses
     * @param calldatas Array of call data
     * @param values Array of ETH values
     * @return successCount Number of successful calls
     */
    function executeBatch(
        address[] calldata targets,
        bytes[] calldata calldatas,
        uint256[] calldata values
    ) external onlyAgent returns (uint256 successCount) {
        require(targets.length == calldatas.length && targets.length == values.length, "Array length mismatch");
        require(targets.length <= 10, "Batch too large"); // Keep batches small for safety
        
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success,) = targets[i].call{value: values[i]}(calldatas[i]);
            if (success) {
                successCount++;
            }
            // Continue on failure for batch operations flexibility
        }
        
        // Increment nonce for replay protection
        _setNonce(_getNonce() + 1);
        
        emit BatchExecuted(address(this), targets.length, successCount);
        return successCount;
    }
    
    /**
     * @notice Execute single call to ETF vault
     * @param callData The call data to send to vault
     * @return result The return data from the call
     */
    function executeVaultCall(bytes calldata callData) external onlyAgent returns (bytes memory result) {
        address vault = _getVault();
        require(vault != address(0), "Vault not set");
        
        (bool success, bytes memory returnData) = vault.call(callData);
        require(success, "Vault call failed");
        
        _setNonce(_getNonce() + 1);
        return returnData;
    }
    
    // =============== ETF OPERATIONS ===============
    
    /**
     * @notice Deposit tokens into the ETF vault
     * @param token Token address
     * @param amount Amount to deposit
     */
    function depositToETF(address token, uint256 amount) external onlyAgent {
        address vault = _getVault();
        require(vault != address(0), "Vault not set");
        
        // Approve vault to spend tokens
        (bool success,) = token.call(
            abi.encodeWithSignature("approve(address,uint256)", vault, amount)
        );
        require(success, "Approve failed");
        
        // Deposit to vault
        (success,) = vault.call(
            abi.encodeWithSignature("deposit(address,uint256)", token, amount)
        );
        require(success, "Deposit failed");
        
        _setNonce(_getNonce() + 1);
    }
    
    /**
     * @notice Withdraw from ETF vault
     * @param shares Amount of shares to burn
     * @param tokenOut Token to receive
     * @param minAmountOut Minimum amount out
     */
    function withdrawFromETF(
        uint256 shares,
        address tokenOut,
        uint256 minAmountOut
    ) external onlyAgent {
        address vault = _getVault();
        require(vault != address(0), "Vault not set");
        
        (bool success,) = vault.call(
            abi.encodeWithSignature("withdraw(uint256,address,uint256)", shares, tokenOut, minAmountOut)
        );
        require(success, "Withdraw failed");
        
        _setNonce(_getNonce() + 1);
    }
    
    /**
     * @notice Transfer tokens directly (useful for moving funds to different chains/protocols)
     * @param token Token address
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transferFunds(address token, address to, uint256 amount) external onlyAgent {
        (bool success,) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success, "Transfer failed");
        
        _setNonce(_getNonce() + 1);
    }
    
    // =============== MANAGEMENT ===============
    
    /**
     * @notice Update the agent (only current agent can do this)
     * @param newAgent New agent address
     */
    function setAgent(address newAgent) external onlyAgent {
        if (newAgent == address(0)) revert InvalidAgent();
        _setAgent(newAgent);
        emit AgentSet(address(this), newAgent);
    }
    
    /**
     * @notice Update the vault (only agent can do this)
     * @param newVault New vault address
     */
    function setVault(address newVault) external onlyAgent {
        if (newVault == address(0)) revert InvalidVault();
        _setVault(newVault);
        emit VaultSet(address(this), newVault);
    }
    
    // =============== VIEW FUNCTIONS ===============
    
    function getVault() external view returns (address) {
        return _getVault();
    }
    
    function getAgent() external view returns (address) {
        return _getAgent();
    }
    
    function getNonce() external view returns (uint256) {
        return _getNonce();
    }
    
    // =============== INTERNAL STORAGE FUNCTIONS ===============
    
    function _getVault() internal view returns (address vault) {
        bytes32 slot = VAULT_SLOT;
        assembly {
            vault := sload(slot)
        }
    }
    
    function _setVault(address vault) internal {
        bytes32 slot = VAULT_SLOT;
        assembly {
            sstore(slot, vault)
        }
    }
    
    function _getAgent() internal view returns (address agent) {
        bytes32 slot = AGENT_SLOT;
        assembly {
            agent := sload(slot)
        }
    }
    
    function _setAgent(address agent) internal {
        bytes32 slot = AGENT_SLOT;
        assembly {
            sstore(slot, agent)
        }
    }
    
    function _getNonce() internal view returns (uint256 nonce) {
        bytes32 slot = NONCE_SLOT;
        assembly {
            nonce := sload(slot)
        }
    }
    
    function _setNonce(uint256 nonce) internal {
        bytes32 slot = NONCE_SLOT;
        assembly {
            sstore(slot, nonce)
        }
    }
    
    // =============== EMERGENCY ===============
    
    /**
     * @notice Emergency function to clear delegation (revert to pure EOA)
     * @dev This can only be called by the EOA itself, not the agent
     */
    function revokeDelegation() external {
        require(msg.sender == address(this), "Only EOA can revoke");
        
        // Clear all storage
        _setVault(address(0));
        _setAgent(address(0));
        _setNonce(0);
    }
    
    // Allow receiving FLOW
    receive() external payable {}
}
