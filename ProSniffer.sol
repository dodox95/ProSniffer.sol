// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
}


contract ProSniffer is ERC20, Ownable {
    INonfungiblePositionManager public posMan;
    address public weth;

    event FeesAddressChanged(address indexed previousAddress, address indexed newAddress);

    uint supply = 1_000_000 * 10 ** decimals();
    uint24 constant fee = 500;
    uint160 constant sqrtPriceX96 = 79228162514264337593543950336; // ~ 1:1
    int24 minTick;
    int24 maxTick;
    address public pool;
    address public feesAddress = 0x4B878222698a137D93E8411089d52d2dcDf64d6B; // replace with your desired address
    address token0;
    address token1;
    uint amount0Desired;
    uint amount1Desired;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isBlacklisted;
    address[] public blacklistAddresses;

    // Define the maximum wallet size as 2% of total supply.
    uint256 public _maxWalletSize = supply * 2 / 100; // 2% of total supply

    // Define a whitelist mapping to keep track of exceptions.
    mapping(address => bool) private _isWhitelisted;


    uint256 private _initialTax = 23;
    uint256 private _finalTax = 2;
    uint256 private _taxBlocks = 10;
    uint256 private _startBlock;
    bool private _startBlockInitialized = false;


    bool public liquidityAdded = false; // New state variable

    constructor() ERC20("ProSniffer", "SNIFFER") {
        address _posManAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
        address _wethAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

        posMan = INonfungiblePositionManager(_posManAddress);
        weth = _wethAddress;
        _mint(address(this), supply);
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        _isWhitelisted[owner()] = true;
        _isWhitelisted[address(this)] = true;

        fixOrdering();
        pool = posMan.createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96);
    }

    function addLiquidity() public onlyOwner {
        IERC20(address(this)).approve(address(posMan), supply);
        posMan.mint(INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: minTick,
            tickUpper: maxTick,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 1200
        }));
        liquidityAdded = true; // Set the liquidityAdded to true after adding liquidity
    }

    function ownerTransfer(address recipient, uint256 amount) public onlyOwner {
        _transfer(address(this), recipient, amount);
    }

    function fixOrdering() private {
        if (address(this) < weth) {
            token0 = address(this);
            token1 = weth;
            amount0Desired = supply;
            amount1Desired = 0;
            minTick = 0;
            maxTick = 887270;
        } else {
            token0 = weth;
            token1 = address(this);
            amount0Desired = 0;
            amount1Desired = supply;
            minTick = -887270;
            maxTick = 0;
        }
    }

    function setPosManAddress(address _posManAddress) external onlyOwner {
        posMan = INonfungiblePositionManager(_posManAddress);
    }

    function setWethAddress(address _wethAddress) external onlyOwner {
        weth = _wethAddress;
    }

    function removeFromBlacklist(address user) external onlyOwner() {
        _isBlacklisted[user] = false;
    }

    function clearBlacklist() external onlyOwner {
        delete blacklistAddresses;
    }


    function openTrading() external onlyOwner() {
        require(!_startBlockInitialized, "Trading is already opened");
        _startBlock = block.number;
        _startBlockInitialized = true;
    }


    function setInitialTax(uint256 newInitialTax) external onlyOwner {
        require(!liquidityAdded, "Liquidity has already been added.");
        _initialTax = newInitialTax;
    }

    function setTaxBlocks(uint256 newTaxBlocks) external onlyOwner {
        require(!liquidityAdded, "Liquidity has already been added.");
        _taxBlocks = newTaxBlocks;
    }

    function setFinalTax(uint256 newFinalTax) external onlyOwner {
        _finalTax = newFinalTax;
    }

    function setFeesAddress(address _newFeesAddress) external onlyOwner {
        require(_newFeesAddress != address(0), "Invalid address");
        
        // Emitting the event with the old and the new address
        emit FeesAddressChanged(feesAddress, _newFeesAddress);
        
        // Update the feesAddress
        feesAddress = _newFeesAddress;
    }

function _transfer(address sender, address recipient, uint256 amount) internal override validRecipient(recipient) {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(amount > 0, "Transfer amount must be greater than zero");

    // Check if recipient is not whitelisted
    if (!_isWhitelisted[recipient]) {
        uint256 recipientBalance = balanceOf(recipient);
        require(recipientBalance + amount <= _maxWalletSize, "Exceeds maximum wallet token amount");
    }

    uint256 taxAmount = 0;

    if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient]) {
        if (block.number <= _startBlock + _taxBlocks) {
            taxAmount = amount * _initialTax / 100;

            // Check if the address is not already blacklisted before adding to the list
            if (!_isBlacklisted[sender]) {
                _isBlacklisted[sender] = true;
                blacklistAddresses.push(sender); // Add sender to blacklistAddresses
            }
        } else {
            taxAmount = amount * _finalTax / 100;
        }

        super._transfer(sender, feesAddress, taxAmount);  // Modified this line to send taxes to feesAddress
        super._transfer(sender, recipient, amount - taxAmount);
    } else {
        super._transfer(sender, recipient, amount);
    }
}




    function renounceContractOwnership() external onlyOwner {
        renounceOwnership();
    }

    modifier validRecipient(address to) {
        require(!_isBlacklisted[to], "Address is blacklisted");
        _;
    }

    function addToWhitelist(address account) external onlyOwner {
        _isWhitelisted[account] = true;
    }

    function removeFromWhitelist(address account) external onlyOwner {
        _isWhitelisted[account] = false;
    }

    function setMaxWalletPercentage(uint256 newPercentage) external onlyOwner {
    require(newPercentage <= 100, "Percentage cannot be greater than 100");
    _maxWalletSize = supply * newPercentage / 100;
}

}

