pragma solidity 0.5.16;

// import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
// import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import './libs/SafeBEP20.sol';
import './interfaces/IPancakeRouter01.sol';
// import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import "./RabbitToken.sol"; //BEP20Token

interface IMigratorRabbit {
    // XXX Migrator must have allowance access to RabbitSwap/pancakeSwap LP tokens.
    // RabbitSwap must mint EXACTLY the same amount of RabbitSwap LP tokens or
    // else something bad will happen. Traditional PancakeSwap does not
    // do that so be careful!
    function migrate(IBEP20 token) external returns (IBEP20);
}

// RabbitStaking is the master of RBT. He can make RBT and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once RBT is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract RabbitStaking is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        string symbol;
        uint256 allocPoint;
        uint256 lastRewardBlock;  // Last block number that RBTs distribution occurs.
        uint256 accRabbitPerShare; // Accumulated RBTs per share, times 1e12. See below.
        uint256 stakedAmount;
        uint256 rewardSent;
    }

    // The RBT TOKEN!
    IBEP20 public rabbit;
    // RBT tokens created per block.
    uint256 public rabbitPerBlock;
    // Bonus muliplier for early rabbit makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // BNB @bsc
    // address public WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    // BNB @bsctestnet
    // address public WETH = 0xaE8E19eFB41e7b96815649A6a60785e1fbA84C1e;

    // swapRouter mainnet@bsc
    // IPancakeRouter01 swapRouter;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // mapping (uint256 => PoolInfo) public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when RBT mining starts.
    uint256 public startBlock;

    bool public open_deposit = true;
    bool public open_withdraw = true;
    bool public open_client = true;

    uint256 private decimal_helper = 1e12;

    IMigratorRabbit private migrator;
    bool private is_migrator = false;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IBEP20 _rabbit,
        uint256 _rabbitPerBlock,
        uint256 _startBlock
    ) public {
        rabbit = _rabbit;
        rabbitPerBlock = _rabbitPerBlock;
        startBlock = _startBlock;
        // swapRouter = IPancakeRouter01(_swapRouter);

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken : _rabbit,
            symbol: _rabbit.symbol(),
            lastRewardBlock : startBlock,
            accRabbitPerShare : 0,
            allocPoint : 1000,
            stakedAmount: 0,
            rewardSent: 0
        }));

        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setDeposit(bool _switch) public onlyOwner {
        open_deposit = _switch;
    }

    function setWithdraw(bool _switch) public onlyOwner {
        open_withdraw = _switch;
    }

    function setClient(bool _switch) public onlyOwner {
        open_client = _switch;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setRewardPerBlock(uint256 _reward) public onlyOwner{
        rabbitPerBlock = _reward;
    }


    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            symbol: _lpToken.symbol(),
            lastRewardBlock : lastRewardBlock,
            accRabbitPerShare : 0,
            allocPoint : _allocPoint,
            stakedAmount: 0,
            rewardSent: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's RBT allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function totalStaked() public view returns (uint256){
        // uint256 valueStaked = 0;
        PoolInfo storage pool = poolInfo[0];
        return pool.stakedAmount.sub(pool.rewardSent);
    }

    // View function to see pending RBTs on frontend.
    function pendingRabbit(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 lpSupply = pool.stakedAmount.sub(pool.rewardSent);
        uint256 accRabbitPerShare = pool.accRabbitPerShare;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 rabbitReward = multiplier.mul(rabbitPerBlock);

            accRabbitPerShare = accRabbitPerShare.add(rabbitReward.mul(decimal_helper).div(lpSupply));
        }

        return user.amount.mul(accRabbitPerShare).div(decimal_helper).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.stakedAmount.sub(pool.rewardSent);
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward = multiplier.mul(rabbitPerBlock);
        pool.accRabbitPerShare = pool.accRabbitPerShare.add(reward.mul(decimal_helper).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to RabbitStaking for RBT allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(open_deposit, 'maintaining');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRabbitPerShare).div(decimal_helper).sub(user.rewardDebt);
            if (pending > 0) {
                safeRabbitTransfer(msg.sender, pending);
                pool.rewardSent = pool.rewardSent.add(pending);
                // swapRouter.swapExactTokensForETH(reward.div(2), 0, path, address(rabbit), block.timestamp+10);
            }
        }

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.stakedAmount = pool.stakedAmount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accRabbitPerShare).div(decimal_helper);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from RabbitStaking.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(open_withdraw, 'maintaining');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "exceed amount stacked");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accRabbitPerShare).div(decimal_helper).sub(user.rewardDebt);
        if (pending > 0) {
            safeRabbitTransfer(msg.sender, pending);
            pool.rewardSent = pool.rewardSent.add(pending);
        }

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.stakedAmount = pool.stakedAmount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount.mul(pool.accRabbitPerShare).div(decimal_helper);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Safe rabbit transfer function, just in case if rounding error causes pool to not have enough RBTs.
    function safeRabbitTransfer(address _to, uint256 _amount) internal {
        rabbit.safeTransfer(_to, _amount);
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorRabbit _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");

        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);

        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }
}
