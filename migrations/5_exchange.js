
const exchange = artifacts.require('./Exchange');
const optionVault = artifacts.require("./OptionVault");

module.exports = (deployer, network, accounts) => deployer
    .then(() => deployExchange(deployer))
    .then(() => displayDeployed(accounts));

async function deployExchange(deployer) {
    var optionVaultInstance = await optionVault.deployed();
    await deployer.deploy(
        exchange,
        optionVaultInstance.address
    );
}

async function displayDeployed(accounts) {
    // var optionVaultInstance = await optionVault.deployed();
    var exchangeInstance = await exchange.deployed();
    // var optionRole = await optionVaultInstance.EXCHANGE();
    // var adminRole = await optionVaultInstance.DEFAULT_ADMIN_ROLE();

    // await optionVaultInstance.grantRole(optionRole, exchangeInstance.address);
    // await optionVaultInstance.revokeRole(adminRole, accounts[0]);
    
    console.log(`=========
    Account: ${accounts[0]}
    Deployed Exchange: ${exchangeInstance.address}
    =========`);
}