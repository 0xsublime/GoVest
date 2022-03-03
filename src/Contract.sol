// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/*
Based on Convex's VestedEscrow: https://github.com/convex-eth/platform/blob/main/contracts/contracts/VestedEscrow.sol
Which in turn is based on Curve's VestedEscrow: https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VestingEscrow.vy

Changes:
- upgrade to Solidity 0.8.10 from 0.6.12
- remove `claimAndStake`
- remove SafeMath
- inline MathUtils library
*/
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract VestedEscrow is ReentrancyGuard{
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    address public admin;
    address public fundAdmin;
    address public stakeContract;

    uint256 public startTime;
    uint256 public totalTime;
    uint256 public initialLockedSupply;
    uint256 public unallocatedSupply;

    mapping(address => uint256) public initialLocked;
    mapping(address => uint256) public totalClaimed;

    address[] public extraRewards;

    event Fund(address indexed recipient, uint256 reward);
    event Claim(address indexed user, uint256 amount);

    constructor(
        address rewardToken_,
        uint256 starttime_,
        uint256 totalTime_,
        address stakeContract_,
        address fundAdmin_
    ) {
        require(starttime_ >= block.timestamp,"start must be future");

        rewardToken = IERC20(rewardToken_);
        startTime = starttime_;
        totalTime = totalTime_;
        admin = msg.sender;
        fundAdmin = fundAdmin_;
        stakeContract = stakeContract_;
    }

    function setAdmin(address _admin) external {
        require(msg.sender == admin, "!auth");
        admin = _admin;
    }

    function setFundAdmin(address _fundadmin) external {
        require(msg.sender == admin, "!auth");
        fundAdmin = _fundadmin;
    }

    function addTokens(uint256 _amount) external returns(bool){
        require(msg.sender == admin, "!auth");

        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        unallocatedSupply = unallocatedSupply + _amount;
        return true;
    }

    function fund(address[] calldata _recipient, uint256[] calldata _amount) external nonReentrant returns(bool){
        require(msg.sender == fundAdmin || msg.sender == admin, "!auth");

        uint256 totalAmount = 0;
        for(uint256 i = 0; i < _recipient.length; i++){
            uint256 amount = _amount[i];
            initialLocked[_recipient[i]] = initialLocked[_recipient[i]] + amount;
            totalAmount = totalAmount + amount;
            emit Fund(_recipient[i],amount);
        }

        initialLockedSupply = initialLockedSupply + totalAmount;
        unallocatedSupply = unallocatedSupply - totalAmount;
        return true;
    }

    function _totalVestedOf(address _recipient, uint256 _time) internal view returns(uint256){
        if(_time < startTime){
            return 0;
        }
        uint256 locked = initialLocked[_recipient];
        uint256 elapsed = _time - startTime;
        uint256 total = min(locked * elapsed / totalTime, locked );
        return total;
    }

    function _totalVested() internal view returns(uint256){
        uint256 _time = block.timestamp;
        if(_time < startTime){
            return 0;
        }
        uint256 locked = initialLockedSupply;
        uint256 elapsed = _time - startTime;
        uint256 total = min(locked * elapsed / totalTime, locked );
        return total;
    }

    function vestedSupply() external view returns(uint256){
        return _totalVested();
    }

    function lockedSupply() external view returns(uint256){
        return initialLockedSupply - _totalVested();
    }

    function vestedOf(address _recipient) external view returns(uint256){
        return _totalVestedOf(_recipient, block.timestamp);
    }

    function balanceOf(address _recipient) external view returns(uint256){
        uint256 vested = _totalVestedOf(_recipient, block.timestamp);
        return vested - totalClaimed[_recipient];
    }

    function lockedOf(address _recipient) external view returns(uint256){
        uint256 vested = _totalVestedOf(_recipient, block.timestamp);
        return initialLocked[_recipient] - vested;
    }

    function claim(address _recipient) public nonReentrant{
        uint256 vested = _totalVestedOf(_recipient, block.timestamp);
        uint256 claimable = vested - totalClaimed[_recipient];

        totalClaimed[_recipient] = totalClaimed[_recipient] + claimable;
        rewardToken.safeTransfer(_recipient, claimable);

        emit Claim(msg.sender, claimable);
    }

    function claim() external{
        claim(msg.sender);
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}