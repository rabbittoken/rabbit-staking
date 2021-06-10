const RabbitBEP20 = artifacts.require('BEP20Token')
const RabbitStaking = artifacts.require('RabbitStaking')
const Web3 = require('web3')
let rewardPerBlock = Web3.utils.toBN((10000000000 / 5 / 360 / 24 / 60 / 20) * 1e18)

module.exports = function(deployer) {
    // deployer.deploy(RabbitBEP20).then(function() {
    //     return deployer.deploy(RabbitStaking, RabbitBEP20.address, rewardPerBlock, 7067739);
    // });

    //bscTestnet
    // deployer.deploy(RabbitBEP20);
    // deployer.deploy(RabbitStaking, '0xb8EeA5bd7306d7eAb349053456B32aAF967D95dD', rewardPerBlock, 7067739);

    //bsc
    // pancakeRouter@bsc 0x10ED43C718714eb63d5aA57B78B54704E256024E
    deployer.deploy(RabbitStaking, '0xbA27d0DA948566Db03f272dC7A90fAdA1f0ED1E3', rewardPerBlock, 7067739);
};