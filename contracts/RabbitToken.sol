pragma solidity 0.5.16;

import './RabbitBEP20.sol';

contract RabbitToken is BEP20Token {

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public onlyOwner {
    _burn(account, amount);
  }

}
