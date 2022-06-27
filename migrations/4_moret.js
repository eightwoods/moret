const moret = artifacts.require('./Moret');
const broker = artifacts.require('./MoretBroker');
const moretGov = artifacts.require('./Govern');
const mathLib = artifacts.require('./MathLib');
const optionVault = artifacts.require("./OptionVault");
// const timelocker = artifacts.require("./TimelockController");

module.exports = (deployer) => deployer
    // .then(() => deployTimeLocker(deployer))
    .then(() => deployBroker(deployer))
    .then(() => deployMoret(deployer))
    .then(() => deployGovernor(deployer))
    .then(() => displayDeployed());

async function deployBroker(deployer) {
    await deployer.link(mathLib, broker);

    var optionVaultInstance = await optionVault.deployed();
    await deployer.deploy(
        broker,
        process.env.STABLE_COIN_ADDRESS,
        optionVaultInstance.address
        );
}

async function deployMoret(deployer) {
    await deployer.link(mathLib, moret);

    var brokerInstance = await broker.deployed();
    await deployer.deploy(
        moret,
        brokerInstance.address
        );
}

// async function deployTimeLocker(deployer) {
//     await deployer.deploy(
//         timelocker,
//         process.env.MIN_DELAY,
//         [process.env.RELAY_ACCOUNT],
//         [process.env.RELAY_ACCOUNT]
//     );
// }

async function deployGovernor(deployer) {
    var moretInstance = await moret.deployed();
    // var timelockerInstance = await timelocker.deployed();

    await deployer.deploy(
        moretGov,
        moretInstance.address
    );
}

async function displayDeployed() {
    var brokerInstance = await broker.deployed();
    var moretInstance = await moret.deployed();
    var moretGovInstance = await moretGov.deployed();
    // var timelockerInstance = await timelocker.deployed();
    // var proposalRole = await timelockerInstance.PROPOSER_ROLE();
    // await timelockerInstance.grantRole(proposalRole, moretGovInstance.address);

    console.log(`=========
    Deployed MoretBroker: ${brokerInstance.address}
    Deployed Moret: ${moretInstance.address}
    Deployed Govern: ${moretGovInstance.address}
    =========`)
}
