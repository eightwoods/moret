const marketMakerFactory = artifacts.require('./MarketMakerFactory');
const moret = artifacts.require("./Moret");
const exchange = artifacts.require("./Exchange");

module.exports = (deployer) => deployer
    .then(() => deployMarketMakerFactory(deployer))
    .then(() => displayDeployed());

async function deployMarketMakerFactory(deployer) {
    var moretInstance = await moret.deployed();
    var exchangeInstance = await exchange.deployed();

    await deployer.deploy(
        marketMakerFactory,
        moretInstance.address,
        exchangeInstance.address
    );
}

async function displayDeployed() {
    const marketMakerFactoryInstance = await marketMakerFactory.deployed();

    console.log(`=========
    Deployed MarketMakerFactory: ${marketMakerFactoryInstance.address}
    =========`);
}