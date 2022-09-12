
const exchange = artifacts.require('./Exchange');
const optionVault = artifacts.require("./OptionVault");

const optionLib = artifacts.require('./OptionLib');
const marketLib = artifacts.require('./MarketLib');
const mathLib = artifacts.require('./MathLib');

module.exports = (deployer, network, accounts) => deployer
    .then(() => deployOptionVault(deployer))
    .then(() => deployExchange(deployer))
    .then(() => displayDeployed(accounts));


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

async function displayDeployed(accounts) {
    var optionVaultInstance = await optionVault.deployed();
    var exchangeInstance = await exchange.deployed();
    var optionRole = await optionVaultInstance.EXCHANGE();
    var adminRole = await optionVaultInstance.DEFAULT_ADMIN_ROLE();

    await optionVaultInstance.grantRole(optionRole, exchangeInstance.address);
    await optionVaultInstance.revokeRole(adminRole, accounts[0]);
    
    console.log(`=========
    Account: ${accounts[0]}
    Deployed OptionVault: ${optionVaultInstance.address}
    Deployed Exchange: ${exchangeInstance.address}
    =========`);
}