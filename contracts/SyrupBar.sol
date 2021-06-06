pragma solidity 0.5.16;

import "./RabbitToken.sol";

// SyrupBar with Governance.
contract SyrupBar is RabbitToken{
    // using BEP20Token for RabbitToken;

    // The RBT TOKEN!
    RabbitToken public rabbit;


    constructor(
        RabbitToken _rabbit
    ) public {
        rabbit = _rabbit;
    }

    // Safe rabbit transfer function, just in case if rounding error causes pool to not have enough RBTs.
    function safeRabbitTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 rabbitBal = rabbit.balanceOf(address(this));
        if (_amount > rabbitBal) {
            rabbit.transfer(_to, rabbitBal);
        } else {
            rabbit.transfer(_to, _amount);
        }
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}

