const poolFactory = artifacts.require('./PoolFactory');

module.exports = (deployer) => deployer
    .then(() => deployPoolactory(deployer))
    .then(() => displayDeployed());

async function deployPoolactory(deployer) {
    await deployer.deploy(
        poolFactory
    );
}

async function displayDeployed() {
    const poolFactoryInstance = await poolFactory.deployed();

    console.log(`=========
    Deployed PoolFactory: ${poolFactoryInstance.address}
    =========`);
}