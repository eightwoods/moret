const moret = artifacts.require('./Moret');
const broker = artifacts.require('./MoretBroker');
const moretGov = artifacts.require('./Govern');
const exchange = artifacts.require("./Exchange");

module.exports = (deployer) => deployer
    .then(() => deployMoret(deployer))
    .then(() => deployGovernor(deployer))
    .then(() => displayDeployed());


async function deployMoret(deployer) {
    var brokerInstance = await broker.deployed();
    await deployer.deploy(
        moret,
        brokerInstance.address
        );
}

async function deployGovernor(deployer) {
    var moretInstance = await moret.deployed();

    await deployer.deploy(
        moretGov,
        moretInstance.address
    );
}

async function displayDeployed() {
    var moretInstance = await moret.deployed();
    var moretGovInstance = await moretGov.deployed();

    console.log(`=========
    Deployed Moret: ${moretInstance.address}
    Deployed Govern: ${moretGovInstance.address}
    =========`)
}
