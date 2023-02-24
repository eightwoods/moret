const poolGovFactory = artifacts.require('./PoolGovernorFactory');

module.exports = (deployer) => deployer
    .then(() => deployPoolGovernorFactory(deployer))
    .then(() => displayDeployed());

async function deployPoolGovernorFactory(deployer) {
    await deployer.deploy(
        poolGovFactory
    );
}

async function displayDeployed() {
    const poolGovFactoryInstance = await poolGovFactory.deployed();

    console.log(`=========
    Deployed PoolGovernorFactory: ${poolGovFactoryInstance.address}
    =========`);
}