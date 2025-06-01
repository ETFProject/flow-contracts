// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MockERC20Token
 * @notice Mock ERC20 token with built-in USDC swap functionality
 */
contract MockERC20Token is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =============== STATE VARIABLES ===============
    
    IERC20 public immutable usdc;
    uint256 public price; // Price in USDC per token (with 6 decimals for USDC)
    uint256 public constant PRICE_DECIMALS = 1e6; // USDC has 6 decimals
    
    // =============== EVENTS ===============
    
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event TokenSwapped(address indexed user, uint256 usdcAmount, uint256 tokenAmount, bool isUsdcToToken);
    
    // =============== CONSTRUCTOR ===============
    
    constructor(
        string memory name,
        string memory symbol,
        address _usdc,
        uint256 initialPrice,
        address _owner
    ) ERC20(name, symbol) Ownable(_owner) {
        usdc = IERC20(_usdc);
        price = initialPrice;
        
        // Mint initial supply to owner
        _mint(_owner, 1000000 * 10**decimals());
    }
    
    // =============== PRICE MANAGEMENT ===============
    
    /**
     * @notice Update the token price
     * @param newPrice New price in USDC per token (6 decimals)
     */
    function updatePrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        
        uint256 oldPrice = price;
        price = newPrice;
        
        emit PriceUpdated(oldPrice, newPrice);
    }
    
    /**
     * @notice Update price via factory (allows factory to update if factory owner matches token owner)
     * @param newPrice New price in USDC per token (6 decimals)
     * @param factoryOwner The owner of the factory making the call
     */
    function updatePriceViaFactory(uint256 newPrice, address factoryOwner) external {
        require(factoryOwner == owner(), "Factory owner must match token owner");
        require(newPrice > 0, "Price must be greater than 0");
        
        uint256 oldPrice = price;
        price = newPrice;
        
        emit PriceUpdated(oldPrice, newPrice);
    }
    
    /**
     * @notice Get current token price
     * @return Current price in USDC per token
     */
    function getPrice() external view returns (uint256) {
        return price;
    }
    
    // =============== SWAP FUNCTIONS ===============
    
    /**
     * @notice Swap USDC for this token
     * @param usdcAmount Amount of USDC to spend
     * @param minTokenAmount Minimum amount of tokens to receive (slippage protection)
     * @return tokenAmount Amount of tokens received
     */
    function swapUsdcForToken(uint256 usdcAmount, uint256 minTokenAmount) 
        external 
        nonReentrant 
        returns (uint256 tokenAmount) 
    {
        require(usdcAmount > 0, "USDC amount must be greater than 0");
        
        // Calculate token amount to give
        // tokenAmount = usdcAmount / price (accounting for decimals)
        // Since USDC has 6 decimals and token has 18 decimals:
        // We need to normalize: usdcAmount (6 decimals) / price (6 decimals) * 10^18 (token decimals)
        tokenAmount = (usdcAmount * 1e18) / price;
        
        require(tokenAmount >= minTokenAmount, "Slippage protection: insufficient output");
        require(balanceOf(address(this)) >= tokenAmount, "Insufficient token liquidity");
        
        // Transfer USDC from user to contract
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        
        // Transfer tokens to user
        _transfer(address(this), msg.sender, tokenAmount);
        
        emit TokenSwapped(msg.sender, usdcAmount, tokenAmount, true);
    }
    
    /**
     * @notice Swap this token for USDC
     * @param tokenAmount Amount of tokens to swap
     * @param minUsdcAmount Minimum amount of USDC to receive (slippage protection)
     * @return usdcAmount Amount of USDC received
     */
    function swapTokenForUsdc(uint256 tokenAmount, uint256 minUsdcAmount) 
        external 
        nonReentrant 
        returns (uint256 usdcAmount) 
    {
        require(tokenAmount > 0, "Token amount must be greater than 0");
        
        // Calculate USDC amount to give
        // usdcAmount = tokenAmount * price (accounting for decimals)
        // Since token has 18 decimals and USDC has 6 decimals:
        // We need to normalize: tokenAmount (18 decimals) * price (6 decimals) / 10^18 (to get 6 decimals)
        usdcAmount = (tokenAmount * price) / 1e18;
        
        require(usdcAmount >= minUsdcAmount, "Slippage protection: insufficient output");
        require(usdc.balanceOf(address(this)) >= usdcAmount, "Insufficient USDC liquidity");
        
        // Transfer tokens from user to contract
        _transfer(msg.sender, address(this), tokenAmount);
        
        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, usdcAmount);
        
        emit TokenSwapped(msg.sender, usdcAmount, tokenAmount, false);
    }
    
    /**
     * @notice Get quote for USDC to token swap
     * @param usdcAmount Amount of USDC
     * @return tokenAmount Amount of tokens that would be received
     */
    function getUsdcToTokenQuote(uint256 usdcAmount) external view returns (uint256 tokenAmount) {
        if (usdcAmount == 0 || price == 0) return 0;
        return (usdcAmount * 1e18) / price;
    }
    
    /**
     * @notice Get quote for token to USDC swap
     * @param tokenAmount Amount of tokens
     * @return usdcAmount Amount of USDC that would be received
     */
    function getTokenToUsdcQuote(uint256 tokenAmount) external view returns (uint256 usdcAmount) {
        if (tokenAmount == 0 || price == 0) return 0;
        return (tokenAmount * price) / 1e18;
    }
    
    // =============== LIQUIDITY MANAGEMENT ===============
    
    /**
     * @notice Add USDC liquidity to the contract
     * @param amount Amount of USDC to add
     */
    function addUsdcLiquidity(uint256 amount) external onlyOwner {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
    }
    
    /**
     * @notice Add token liquidity to the contract
     * @param amount Amount of tokens to add
     */
    function addTokenLiquidity(uint256 amount) external onlyOwner {
        _transfer(msg.sender, address(this), amount);
    }
    
    /**
     * @notice Remove USDC liquidity from the contract
     * @param amount Amount of USDC to remove
     */
    function removeUsdcLiquidity(uint256 amount) external onlyOwner {
        usdc.safeTransfer(msg.sender, amount);
    }
    
    /**
     * @notice Remove token liquidity from the contract
     * @param amount Amount of tokens to remove
     */
    function removeTokenLiquidity(uint256 amount) external onlyOwner {
        _transfer(address(this), msg.sender, amount);
    }
    
    /**
     * @notice Get contract's USDC balance
     * @return USDC balance
     */
    function getUsdcBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
    
    /**
     * @notice Get contract's token balance
     * @return Token balance
     */
    function getTokenBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }
}

/**
 * @title ERC20MockTokenFactory
 * @notice Factory contract for creating mock ERC20 tokens with swap functionality
 */
contract ERC20MockTokenFactory is Ownable {
    
    // =============== STATE VARIABLES ===============
    
    IERC20 public immutable usdc;
    MockERC20Token[] public tokens;
    mapping(address => bool) public isValidToken;
    
    // =============== EVENTS ===============
    
    event TokenCreated(
        address indexed tokenAddress,
        string name,
        string symbol,
        uint256 initialPrice,
        address indexed creator
    );
    
    // =============== CONSTRUCTOR ===============
    
    constructor(address _usdc, address _owner) Ownable(_owner) {
        usdc = IERC20(_usdc);
    }
    
    // =============== TOKEN CREATION ===============
    
    /**
     * @notice Create a new mock ERC20 token with swap functionality
     * @param name Token name
     * @param symbol Token symbol
     * @param initialPrice Initial price in USDC per token (6 decimals)
     * @return tokenAddress Address of the created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialPrice
    ) external onlyOwner returns (address tokenAddress) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(initialPrice > 0, "Initial price must be greater than 0");
        
        // Create new mock token
        MockERC20Token newToken = new MockERC20Token(
            name,
            symbol,
            address(usdc),
            initialPrice,
            msg.sender
        );
        
        tokenAddress = address(newToken);
        tokens.push(newToken);
        isValidToken[tokenAddress] = true;
        
        emit TokenCreated(tokenAddress, name, symbol, initialPrice, msg.sender);
    }
    
    /**
     * @notice Create multiple tokens at once
     * @param names Array of token names
     * @param symbols Array of token symbols
     * @param initialPrices Array of initial prices
     * @return tokenAddresses Array of created token addresses
     */
    function createMultipleTokens(
        string[] memory names,
        string[] memory symbols,
        uint256[] memory initialPrices
    ) external onlyOwner returns (address[] memory tokenAddresses) {
        require(names.length == symbols.length, "Arrays length mismatch");
        require(names.length == initialPrices.length, "Arrays length mismatch");
        require(names.length > 0, "Arrays cannot be empty");
        
        tokenAddresses = new address[](names.length);
        
        for (uint256 i = 0; i < names.length; i++) {
            // Create token directly without external call
            require(bytes(names[i]).length > 0, "Name cannot be empty");
            require(bytes(symbols[i]).length > 0, "Symbol cannot be empty");
            require(initialPrices[i] > 0, "Initial price must be greater than 0");
            
            // Create new mock token
            MockERC20Token newToken = new MockERC20Token(
                names[i],
                symbols[i],
                address(usdc),
                initialPrices[i],
                msg.sender
            );
            
            address tokenAddress = address(newToken);
            tokens.push(newToken);
            isValidToken[tokenAddress] = true;
            tokenAddresses[i] = tokenAddress;
            
            emit TokenCreated(tokenAddress, names[i], symbols[i], initialPrices[i], msg.sender);
        }
    }
    
    // =============== VIEW FUNCTIONS ===============
    
    /**
     * @notice Get total number of created tokens
     * @return Number of tokens
     */
    function getTokenCount() external view returns (uint256) {
        return tokens.length;
    }
    
    /**
     * @notice Get token address by index
     * @param index Index of the token
     * @return Token address
     */
    function getToken(uint256 index) external view returns (address) {
        require(index < tokens.length, "Index out of bounds");
        return address(tokens[index]);
    }
    
    /**
     * @notice Get all created token addresses
     * @return Array of token addresses
     */
    function getAllTokens() external view returns (address[] memory) {
        address[] memory tokenAddresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAddresses[i] = address(tokens[i]);
        }
        return tokenAddresses;
    }
    
    /**
     * @notice Check if an address is a valid token created by this factory
     * @param tokenAddress Address to check
     * @return True if valid token
     */
    function isTokenValid(address tokenAddress) external view returns (bool) {
        return isValidToken[tokenAddress];
    }
    
    /**
     * @notice Get token information
     * @param tokenAddress Address of the token
     * @return name Token name
     * @return symbol Token symbol
     * @return price Current price
     * @return usdcBalance Contract's USDC balance
     * @return tokenBalance Contract's token balance
     */
    function getTokenInfo(address tokenAddress) 
        external 
        view 
        returns (
            string memory name,
            string memory symbol,
            uint256 price,
            uint256 usdcBalance,
            uint256 tokenBalance
        ) 
    {
        require(isValidToken[tokenAddress], "Invalid token address");
        
        MockERC20Token token = MockERC20Token(tokenAddress);
        
        name = token.name();
        symbol = token.symbol();
        price = token.getPrice();
        usdcBalance = token.getUsdcBalance();
        tokenBalance = token.getTokenBalance();
    }
    
    // =============== BATCH OPERATIONS ===============
    
    /**
     * @notice Update prices for multiple tokens
     * @param tokenAddresses Array of token addresses
     * @param newPrices Array of new prices
     */
    function updateMultiplePrices(
        address[] memory tokenAddresses,
        uint256[] memory newPrices
    ) external onlyOwner {
        require(tokenAddresses.length == newPrices.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            require(isValidToken[tokenAddresses[i]], "Invalid token address");
            // Use the factory-specific update function
            MockERC20Token(tokenAddresses[i]).updatePriceViaFactory(newPrices[i], msg.sender);
        }
    }
    
    /**
     * @notice Add USDC liquidity to multiple tokens
     * @param tokenAddresses Array of token addresses
     * @param amounts Array of USDC amounts to add
     */
    function addUsdcLiquidityToMultiple(
        address[] memory tokenAddresses,
        uint256[] memory amounts
    ) external onlyOwner {
        require(tokenAddresses.length == amounts.length, "Arrays length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        // Transfer total USDC from owner
        usdc.transferFrom(msg.sender, address(this), totalAmount);
        
        // Distribute to tokens
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            require(isValidToken[tokenAddresses[i]], "Invalid token address");
            usdc.transfer(tokenAddresses[i], amounts[i]);
        }
    }
}