const RabbitBEP20 = artifacts.require('BEP20Token')
const RabbitStaking = artifacts.require('RabbitStaking')
let rewardPerBlock = Math.ceil(64.3 * 3)

module.exports = function(deployer) {
    deployer.deploy(RabbitBEP20).then(function() {
        return deployer.deploy(RabbitStaking, RabbitBEP20.address, rewardPerBlock, 9406219);
    });
};