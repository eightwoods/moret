
const exchange = artifacts.require('./Exchange');
const optionVault = artifacts.require("./OptionVault");

const optionLib = artifacts.require('./OptionLib');
const marketLib = artifacts.require('./MarketLib');
const mathLib = artifacts.require('./MathLib');

module.exports = (deployer) => deployer
    .then(() => deployOptionVault(deployer))
    .then(() => deployExchange(deployer))
    .then(() => displayDeployed());


async function deployOptionVault(deployer) {
    await deployer.link(mathLib, optionVault);
    await deployer.link(optionLib, optionVault);
    await deployer.link(marketLib, optionVault);
    
    await deployer.deploy(optionVault);
}

async function deployExchange(deployer) {
    await deployer.link(mathLib, exchange);
    // await deployer.link(optionLib, exchange);
    await deployer.link(marketLib, exchange);

    var optionVaultInstance = await optionVault.deployed();
    await deployer.deploy(
        exchange,
        optionVaultInstance.address
    );
}

async function displayDeployed() {
    var optionVaultInstance = await optionVault.deployed();
    var exchangeInstance = await exchange.deployed();
    var optionRole = await optionVaultInstance.EXCHANGE();
    
    await optionVaultInstance.grantRole(optionRole, exchangeInstance.address);
    
    console.log(`=========
    Deployed OptionVault: ${optionVaultInstance.address}
    Deployed Exchange: ${exchangeInstance.address}
    =========`);
}