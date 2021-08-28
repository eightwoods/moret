
const exchange = artifacts.require('./MoretExchange');
const marketMaker = artifacts.require('./MoretMarketMaker');
const volToken = artifacts.require("./VolatilityToken");
const optionVault = artifacts.require("./OptionVault");

module.exports = (deployer) => deployer
    .then(() => deployExchange(deployer))
    .then(() => displayDeployed());

async function deployExchange(deployer) {
    var volTokenInstance = await volToken.deployed();
    var marketMakerInstance = await marketMaker.deployed();
    var optionVaultInstance = await optionVault.deployed();

    await deployer.deploy(
        exchange,
        marketMakerInstance.addres,
        optionVaultInstance.address,
        volTokenInstance.address
    );

    const exchangeInstance = await exchange.deployed();
    assignRoles(marketMakerInstance, optionVaultInstance, exchangeInstance);
}

async function assignRoles(marketMakerInstance, optionVaultInstance, exchangeInstance) {
    await optionVaultInstance.grantRole(optionVaultInstance.EXCHANGE_ROLE, exchangeInstance.address);
    await marketMakerInstance.grantRole(marketMakerInstance.EXCHANGE_ROLE, exchangeInstance.address);
}

async function displayDeployed() {
    const exchangeInstance = await exchange.deployed();
    console.log(`=========
    Deployed Exchange: ${exchangeInstance.address}
    =========`)
}