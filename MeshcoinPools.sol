// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts@3.2.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@3.2.0/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts@3.2.0/math/SafeMath.sol";
import "@openzeppelin/contracts@3.2.0/access/Ownable.sol";
import "./Meshcoin.sol";

// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Meshcoin is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MeshcoinPools is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardRemain;   // Remain rewards

        // We do some fancy math here. Basically, any point in time, the amount of Meshcoins
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) + user.rewardRemain - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User calc the pending rewards and record at rewardRemain.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. Meshcoins to distribute per block.
        uint256 lastRewardBlock;    // Last block number that Meshcoins distribution occurs.
        uint256 accRewardPerShare;  // Accumulated Meshcoins per share, times 1e18. See below.
        uint256 totalAmount;        // Total amount of current pool deposit.
        uint256 pooltype;           // pool type, 1 = Single ERC20 or 2 = LP Token or 3 = nft Pool
    }

    // The Meshcoin!
    Meshcoin public msc;
    // Dev address.
    address public devaddr;
    // Operater address.
    address public opeaddr;
    // Meshcoins created per block.
    uint256 public rewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // the Meshcoins distribution
    uint256 public rewardDistributionFactor = 1e9;
    // The block number when Meshcoin mining starts.
    uint256 public startBlock;
    // Reduction
    uint256 public reductionBlockPeriod;    // 60/3*60*24*7 = 201600
    uint256 public maxReductionCount;
    uint256 public nextReductionBlock;
    uint256 public reductionCounter;
    // Block number when bonus MSC reduction period ends.
    uint256 public bonusStableBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor (
        Meshcoin _msc,
        address _devaddr,
        address _opeaddr,
        uint256 _rewardPerBlock,
        uint256 _startBlock
    ) public {

        require(_devaddr != address(0), "_devaddr address cannot be 0");
        require(_opeaddr != address(0), "_opeaddr address cannot be 0");

        msc = _msc;
        devaddr = _devaddr;
        opeaddr = _opeaddr;
        startBlock = _startBlock;
        rewardPerBlock = _rewardPerBlock;

        reductionBlockPeriod = 201600;  // 60/3*60*24*7 = 201600
        maxReductionCount = 12;

        bonusStableBlock = _startBlock.add(reductionBlockPeriod.mul(maxReductionCount));
        nextReductionBlock = _startBlock.add(reductionBlockPeriod);
    }

    modifier validatePoolByPid(uint256 _pid) { 
        require (_pid < poolInfo.length , "Pool does not exist") ;
        _;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint256 _pooltype) external onlyOwner {

        uint256 _len = poolInfo.length;
        for(uint256 i = 0; i < _len; i++){
            require(_lpToken != poolInfo[i].lpToken, "LPToken already exists");
        }

        massUpdatePools();
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRewardPerShare: 0,
            totalAmount: 0,
            pooltype: _pooltype
        }));
    }

    // Set the number of msc produced by each block
    function setRewardPerBlock(uint256 _newPerBlock) external onlyOwner {
        massUpdatePools();
        rewardPerBlock = _newPerBlock;
    }

    function setRewardDistributionFactor(uint256 _rewardDistributionFactor) external onlyOwner {
        massUpdatePools();
        rewardDistributionFactor = _rewardDistributionFactor;
    }

    // Update the given pool's Meshcoin allocation point. Can only be called by the owner.
    function setAllocPoint(uint256 _pid, uint256 _allocPoint) external onlyOwner validatePoolByPid(_pid) {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Pooltype to set pool display type on frontend.
    function setPoolType(uint256 _pid, uint256 _pooltype) external onlyOwner validatePoolByPid(_pid) {
        poolInfo[_pid].pooltype = _pooltype;
    }

    function setReductionArgs(uint256 _reductionBlockPeriod, uint256 _maxReductionCount) external onlyOwner {

        nextReductionBlock = nextReductionBlock.sub(reductionBlockPeriod).add(_reductionBlockPeriod);
        bonusStableBlock = nextReductionBlock.add(_reductionBlockPeriod.mul(_maxReductionCount.sub(reductionCounter).sub(1)));

        reductionBlockPeriod = _reductionBlockPeriod;
        maxReductionCount = _maxReductionCount;
    }

    // Return reward multiplier over the given _from to _to block.
    function getBlocksReward(uint256 _from, uint256 _to) public view returns (uint256 value) {
        uint256 prevReductionBlock = nextReductionBlock.sub(reductionBlockPeriod);
        if ((_from >= prevReductionBlock && _to <= nextReductionBlock) || 
            (_from > bonusStableBlock))
        {
            value = getBlockReward(_to.sub(_from), rewardPerBlock, reductionCounter);
        }
        else if (_from < prevReductionBlock && _to < nextReductionBlock)
        {
            uint256 part1 = getBlockReward(_to.sub(prevReductionBlock), rewardPerBlock, reductionCounter);
            uint256 part2 = getBlockReward(prevReductionBlock.sub(_from), rewardPerBlock, reductionCounter.sub(1));
            value = part1.add(part2);
        }
        else // if (_from > prevReductionBlock && _to > nextReductionBlock)
        {
            uint256 part1 = getBlockReward(_to.sub(nextReductionBlock), rewardPerBlock, reductionCounter.add(1));
            uint256 part2 = getBlockReward(nextReductionBlock.sub(_from), rewardPerBlock, reductionCounter);
            value = part1.add(part2);
        }

        value = value.mul(rewardDistributionFactor).div(1e9);
    }

    // Return reward per block
    function getBlockReward(uint256 _blockCount, uint256 _rewardPerBlock, uint256 _reductionCounter) internal view returns (uint256) {
        uint256 reward = _blockCount.mul(_rewardPerBlock);
        if (_reductionCounter == 0) {
            return reward;
        }else if (_reductionCounter >= maxReductionCount) {
            return reward.mul(75).div(1000);
        }
        // _reductionCounter no more than maxReductionCount (12)
        return reward.mul(80 ** _reductionCounter).div(100 ** _reductionCounter);
    }

    // View function to see pending Meshcoins on frontend.
    function pendingRewards(uint256 _pid, address _user) public validatePoolByPid(_pid) view returns (uint256 value) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        value = totalRewards(pool, user).add(user.rewardRemain).sub(user.rewardDebt);
    }

    function totalRewards(PoolInfo memory _pool, UserInfo memory _user) internal view returns (uint256 value) {
        uint256 accRewardPerShare = _pool.accRewardPerShare;
        if (block.number > _pool.lastRewardBlock && _pool.totalAmount != 0) {
            uint256 blockReward = getBlocksReward(_pool.lastRewardBlock, block.number);
            uint256 poolReward = blockReward.mul(_pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(poolReward.mul(1e18).div(_pool.totalAmount));
        }
        value = _user.amount.mul(accRewardPerShare).div(1e18);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.allocPoint == 0) {
            return;
        }
        if (block.number > nextReductionBlock) {
            if(reductionCounter >= maxReductionCount) {
                bonusStableBlock = nextReductionBlock;
            }else{
                nextReductionBlock = nextReductionBlock.add(reductionBlockPeriod);
                reductionCounter = reductionCounter.add(1);
            }
        }
        if (pool.totalAmount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockReward = getBlocksReward(pool.lastRewardBlock, block.number);
        uint256 poolReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        if(poolReward > 0) {
            // 1998%% for pools, 500%% for team and 200%% for business
            msc.liquidityMiningMint(devaddr, poolReward.mul(500).div(1998));
            msc.liquidityMiningMint(opeaddr, poolReward.mul(200).div(1998));
            msc.liquidityMiningMint(address(this), poolReward);
        }
        pool.accRewardPerShare = pool.accRewardPerShare.add(poolReward.mul(1e18).div(pool.totalAmount));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for Meshcoin allocation.
    function deposit(uint256 _pid, uint256 _amount) external validatePoolByPid(_pid) {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount > 0) {
            user.rewardRemain = pendingRewards(_pid, msg.sender);
            // user.rewardDebt = 0;
        }
        if(_amount > 0) {
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        }
        user.rewardDebt = totalRewards(pool, user);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MeshcoinPool.
    function withdraw(uint256 _pid, uint256 _amount) external validatePoolByPid(_pid){
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        user.rewardRemain = pendingRewards(_pid, msg.sender);
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = totalRewards(pool, user);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimAll(uint256 _pid) external validatePoolByPid(_pid) returns(uint256 value){
        updatePool(_pid);
        value = pendingRewards(_pid, msg.sender);
        // require(value >= 0, "claim: not good");
        if (value > 0) {
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][msg.sender];
            user.rewardRemain = 0;
            user.rewardDebt = totalRewards(pool, user);
            safeMscTransfer(msg.sender, value);
        }
        emit Claim(msg.sender, _pid, value);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external validatePoolByPid(_pid){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardRemain = 0;
        pool.totalAmount = pool.totalAmount.sub(amount);
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe Meshcoin transfer function, just in case if rounding error causes pool to not have enough Meshcoins.
    function safeMscTransfer(address _to, uint256 _amount) internal {
        uint256 mscBalance = msc.balanceOf(address(this));
        if (_amount > mscBalance) {
            msc.transfer(_to, mscBalance);
        } else {
            msc.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(_devaddr != address(0), "_devaddr address cannot be 0");
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
    
    // Update ope address by the previous ope.
    function ope(address _opeaddr) external {
        require(_opeaddr != address(0), "_devaddr address cannot be 0");
        require(msg.sender == opeaddr, "ope: wut?");
        opeaddr = _opeaddr;
    }

    // If the user transfers TH to contract, it will revert
    receive() external payable {
        revert();
    }
}
