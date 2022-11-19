const marketMakerFactory = artifacts.require('./MarketMakerFactory');
const poolFactory = artifacts.require('./PoolFactory');
const poolGovFactory = artifacts.require('./PoolGovernorFactory');
const moret = artifacts.require("./Moret");
const exchange = artifacts.require("./Exchange");

module.exports = (deployer) => deployer
    .then(() => deployMarketMakerFactory(deployer))
    .then(() => deployPoolactory(deployer))
    .then(() => deployPoolGovernorFactory(deployer))
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

async function deployPoolactory(deployer) {
    await deployer.deploy(
        poolFactory
    );
}

async function deployPoolGovernorFactory(deployer) {
    await deployer.deploy(
        poolGovFactory
    );
}

async function displayDeployed() {
    const marketMakerFactoryInstance = await marketMakerFactory.deployed();
    const poolFactoryInstance = await poolFactory.deployed();
    const poolGovFactoryInstance = await poolGovFactory.deployed();

    console.log(`=========
    Deployed MarketMakerFactory: ${marketMakerFactoryInstance.address}
    Deployed PoolFactory: ${poolFactoryInstance.address}
    Deployed PoolGovernorFactory: ${poolGovFactoryInstance.address}
    =========`);
}