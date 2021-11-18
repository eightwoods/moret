
const exchange = artifacts.require('./Exchange');
const marketMaker = artifacts.require('./MoretMarketMaker');
// const volToken = artifacts.require("./VolatilityToken");
const marketLib = artifacts.require('./MarketLibrary');
const optionVault = artifacts.require("./OptionVault");
const optionLib = artifacts.require('./OptionLibrary');

module.exports = (deployer) => deployer
    .then(() => deployExchange(deployer))
    .then(() => displayDeployed());

async function deployExchange(deployer) {
    // var volTokenInstance = await volToken.deployed();
    var marketMakerInstance = await marketMaker.deployed();
    var optionVaultInstance = await optionVault.deployed();
    await deployer.link(optionLib, exchange);
    await deployer.link(marketLib, exchange);

    await deployer.deploy(
        exchange,
        marketMakerInstance.address,
        optionVaultInstance.address
    );
}

async function displayDeployed() {
    var marketMakerInstance = await marketMaker.deployed();
    var optionVaultInstance = await optionVault.deployed();
    var exchangeInstance = await exchange.deployed();
    var optionRole = await optionVaultInstance.EXCHANGE_ROLE();
    var marketRole = await marketMakerInstance.EXCHANGE_ROLE();

    await optionVaultInstance.grantRole(optionRole, exchangeInstance.address);
    await marketMakerInstance.grantRole(marketRole, exchangeInstance.address);

    console.log(`=========
    Deployed Exchange: ${exchangeInstance.address}
    =========`);
}