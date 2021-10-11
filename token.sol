// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// @openzeppelin libs
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// NOTE: as of 0.8.0 SafeMath is not necessary anymore

contract OBToken is ERC20Burnable, Ownable {
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

    /** @dev Sets Development wallet address
      * @param addr destination address
      */
    function setDevWallet(address addr) external onlyOwner {
        setFeelessAddress(addr, 1);
        _dev_wallet = addr;
    }

    /** @dev Sets protocol fee
      * @param fee_divider The fee divider (1/fee, where 0 < fee < 1)
      */
    function setFee(uint256 fee_divider) external onlyOwner {
        // Restrict fee range to prevent abuse from our side
        require(fee_divider >= 20, "Fee needs to be lower or equal to 5%");
        _fee_divider = fee_divider;
    }
    
    /** @dev Get current protocol fee
      * @return fee divider (1/fee)
      */
    function currentFeeDivider() external view returns (uint256) {
        return _fee_divider;
    }

    /** @dev Set if an address should pay protocol fees (some addresses need to be whitelisted)
      * @param addr Address to configure
      * @param isFeeless Fee structure the addr gets (0 = protocol fee, 1 = no fees)
      */
    function setFeelessAddress(address addr, uint isFeeless) public onlyOwner {
        require(addr != _dev_wallet, "Fee setting of dev wallet can't be changed as it needs to be 1");
    	_feelessmembers[addr] = isFeeless;
    }

    /** @dev Adds a vesting scheme to the contract
      * @param vestingamounts The amount the needs to be locked at each point in time (in `_vestinginterval` increments from deployment)
      * @return Vesting identifier
      */
    function addVestingScheme(uint256[] calldata vestingamounts) external onlyOwner returns (uint) {
        _maxvestingid += 1;
        _vestingschedules[_maxvestingid] = vestingamounts;
        return _maxvestingid;
    }

    /** @dev Adds an address to a vesting scheme (one per address)
      * @param addr Address to configure
      * @param vestingid Vesting id to add address to
      */
    function addVestingAddress(address addr, uint vestingid) external onlyOwner {
    	require(_vestingaddresses[addr] == 0, "Cannot change vesting schedule after it's set");
        _vestingaddresses[addr] = vestingid;
    }

    /** @dev Get vesting requirements for a particular address
      * @param addr Address to get requirements for
      * @return the locked token requirements for `_vestinginterval` increments since contract creation
      */ 
    function vestingRequirements(address addr) external view returns (uint256[] memory) {
    	uint vestid = _vestingaddresses[addr];
        return _vestingschedules[vestid];
    }

    /** @dev Transfers tokens (override for vesting and protocol fee)
      * @param sender The origin of the tokens
      * @param recipient The destination of the tokens
      * @param amount The amount to transfer
      */
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

