pragma solidity 0.5.16;

// import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
// import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import './libs/SafeBEP20.sol';
import './interfaces/IPancakeRouter01.sol';
// import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import "./RabbitToken.sol"; //BEP20Token

interface IMigratorRabbit {
    // Perform LP token migration from legacy PancakeSwap to CakeSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to PancakeSwap LP tokens.
    // CakeSwap must mint EXACTLY the same amount of CakeSwap LP tokens or
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
        uint256 lastRewardBlock;
        //
        // We do some fancy math here. Basically, any point in time, the amount of RBTs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRabbitPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRabbitPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 tokenDecimal;
        uint256 allocPoint;       // How many allocation points assigned to this pool. RBTs to distribute per block.
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
	// pancakeRouter mainnet@bsc
	// IPancakeRouter01 pancakeRouter = IPancakeRouter01(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    // pancakeRouter mainnet@bsctestnet
    IPancakeRouter01 pancakeRouter = IPancakeRouter01(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);

    // BNB @bsc
	address public WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
	// BNB @bsctestnet
	address public WETH_test = 0xaE8E19eFB41e7b96815649A6a60785e1fbA84C1e;

    address[] path;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // mapping (uint256 => PoolInfo) public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when RBT mining starts.
    uint256 public startBlock;

    bool public is_mountained = false;
    IMigratorRabbit public migrator;

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

        uint256 _base = 10;
        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _rabbit,
            tokenDecimal: _base ** _rabbit.decimals(),
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accRabbitPerShare: 0,
            stakedAmount: 0,
            rewardSent: 0
        }));

        totalAllocPoint = 1000;

        path = new address[](2);
        path[0] = address(rabbit);
        path[1] = WETH;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setOffline(bool is_online) public onlyOwner {
        is_mountained = is_online;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getRewardPerBlock() external view returns (uint256){
        return rabbitPerBlock;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        uint256 _base = 10;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            tokenDecimal: _base ** _lpToken.decimals(),
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRabbitPerShare: 0,
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
        uint256 amountStaked = 0;
        for(uint pid = 0; pid<poolInfo.length; ++pid){
            amountStaked = amountStaked.add(poolInfo[pid].stakedAmount);
        }

        return amountStaked;
    }

    // View function to see pending RBTs on frontend.
    function pendingRabbit(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 rabbitRewardPending = 0;

        if (user.lastRewardBlock > 0 && block.number > user.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(user.lastRewardBlock, block.number);
            uint256 rabbitReward = multiplier.mul(rabbitPerBlock).mul(pool.tokenDecimal).mul(1e12);
            rabbitRewardPending = rabbitReward.mul(user.amount).div(pool.stakedAmount).div(1e12); //weight
        }

        return rabbitRewardPending.mul(9).div(10);
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
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        // uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        // uint256 rabbitReward = multiplier.mul(rabbitPerBlock).mul(10 ** pool.lpToken.decimals());
        // uint256 rabbitRewardUser = user.amount.div(pool.stakedAmount).mul(rabbitReward); //weight

        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to RabbitStaking for RBT allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(!is_mountained, 'mountaining');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount > 0) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            uint256 pending = 0;
            if (user.lastRewardBlock >0 && block.number > user.lastRewardBlock && lpSupply != 0) {
                uint256 multiplier = getMultiplier(user.lastRewardBlock, block.number);
                uint256 rabbitReward = multiplier.mul(rabbitPerBlock).mul(pool.tokenDecimal).mul(1e12);
                pending = rabbitReward.mul(user.amount).div(pool.stakedAmount).div(1e12); //weight
            }

			uint256 pendingReal = pending.mul(9).div(10);
            if(pendingReal > 0) {
                safeRabbitTransfer(msg.sender, pendingReal);
                user.rewardDebt = user.rewardDebt.add(pending);
                if(user.lastRewardBlock <= block.number)
                    user.lastRewardBlock = block.number;
                pool.rewardSent = pool.rewardSent.add(pending);

                // uint256 reward = pending.div(10);
	    	    // pancakeRouter.swapExactTokensForETH(reward.div(2), 0, path, address(rabbit), block.timestamp+10);
            }
        }

        updatePool(_pid);
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            if(user.lastRewardBlock <= block.number)
                user.lastRewardBlock = block.number;
            pool.stakedAmount = pool.stakedAmount.add(_amount);
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from RabbitStaking.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(!is_mountained, 'mountaining');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 pending = 0;
        if (user.lastRewardBlock>0 && block.number > user.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(user.lastRewardBlock, block.number);
            uint256 rabbitReward = multiplier.mul(rabbitPerBlock).mul(pool.tokenDecimal).mul(1e12);
            pending = rabbitReward.mul(user.amount).div(pool.stakedAmount).div(1e12); //weight
        }
        uint256 pendingReal = pending.mul(9).div(10);
        if(pendingReal > 0) {
            safeRabbitTransfer(msg.sender, pendingReal);
            user.rewardDebt = user.rewardDebt.add(pending);
            if(user.lastRewardBlock <= block.number)
                user.lastRewardBlock = block.number;
            pool.rewardSent = pool.rewardSent.add(pending);

            // uint256 reward = pending.div(10);
            // pancakeRouter.swapExactTokensForETH(reward.div(2), 0, path, address(rabbit), block.timestamp+10);
        }

        updatePool(_pid);
        if(_amount > 0) {
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            user.amount = user.amount.sub(_amount);
            if(user.lastRewardBlock <= block.number)
                user.lastRewardBlock = block.number;
            pool.stakedAmount = pool.stakedAmount.sub(_amount);
        }

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
