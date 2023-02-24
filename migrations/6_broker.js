const broker = artifacts.require('./MoretBroker');
const exchange = artifacts.require("./Exchange");

module.exports = (deployer) => deployer
    .then(() => deployBroker(deployer))
    .then(() => displayDeployed());

async function deployBroker(deployer) {
    var exchangeInstance = await exchange.deployed();
    await deployer.deploy(
        broker,
        process.env.STABLE_COIN_ADDRESS,
        exchangeInstance.address
    );
}

async function displayDeployed() {
    var brokerInstance = await broker.deployed();

    console.log(`=========
    Deployed MoretBroker: ${brokerInstance.address}
    =========`)
}
