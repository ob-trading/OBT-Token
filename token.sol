// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// @openzeppelin libs
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OBToken is ERC20, ERC20Burnable, Ownable {
    using SafeMath for uint256;

    // Vesting in 6-months interval (uint identifies the schedule)
    // The schedules define the amount an address is NOT allow to use (the vested amount)
    // This allows users to buy more and use that amount freely, but not the amount obtained through a partner program
    uint private _vestinginterval;
    uint private _maxvestingid;
    mapping (address => uint) private _vestingaddresses;
    mapping (uint => uint256[]) private _vestingschedules;
    mapping (address => uint) private _feelessmembers;
    uint256 private _fee_divider; // int(1/fee)
    address private _dev_wallet;
    uint private _deploytime;
    
    constructor() ERC20("OBToken", "OBT") Ownable() {
        _mint(msg.sender, 10_000_000 * 10 ** 18);
        _deploytime = block.timestamp;
        _vestinginterval = 2246400; // 6-months in seconds
        _maxvestingid = 0;
        _fee_divider = 200; // 0.5%
    }

    function setDevWallet(address addr) public onlyOwner {
        _dev_wallet = addr;
        setFeelessAddress(addr, 1);
    }

    function setFee(uint256 fee_divider) public onlyOwner {
        // Restrict fee range to prevent abuse from our side
        require(fee_divider >= 20, "Fee needs to be lower or equal to 5%");
        _fee_divider = fee_divider;
    }
    
    function currentFeeDivider() public view returns (uint256) {
        return _fee_divider;
    }

    function setFeelessAddress(address addr, uint isFeeless) public onlyOwner {
    	_feelessmembers[addr] = isFeeless;
    }

    function addVestingScheme(uint256[] calldata vestingamounts) public onlyOwner returns (uint) {
        _maxvestingid += 1;
        _vestingschedules[_maxvestingid] = vestingamounts;
        return _maxvestingid;
    }

    function addVestingAddress(address addr, uint vestingid) public onlyOwner {
    	require(_vestingaddresses[addr] == 0, "Cannot change vesting schedule after it's set");
        _vestingaddresses[addr] = vestingid;
    }

    function vestingRequirements(address addr) public view returns (uint256[] memory) {
    	uint vestid = _vestingaddresses[addr];
        return _vestingschedules[vestid];
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        uint256 senderBalance = balanceOf(sender);
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        // Check for active vesting schedule
        if (_vestingaddresses[sender] != 0) {
            // User has vesting schedule
            uint vestid = _vestingaddresses[sender];
            uint vestindex = (block.timestamp - _deploytime) / _vestinginterval;

            // Check if the vesting schedule has already ended (out-of-index)
            if (vestindex < _vestingschedules[vestid].length) {
                uint256 balance_left = senderBalance - amount;
                require(balance_left > _vestingschedules[vestid][vestindex], "Amount to transfer is not allowed by the vesting scheme");
            }
        }

	    // If either side is whitelisted for fees, don't subtract fees
        if (_feelessmembers[sender] == 0 && _feelessmembers[recipient] == 0) {
            uint256 fee = amount / _fee_divider;
            _burn(sender, fee/2);
            _transfer(sender, _dev_wallet, fee/2);
            amount -= (fee/2) * 2; // floored when div, so need to recalc from div
        }
        return super._transfer(sender, recipient, amount);
    }
}

