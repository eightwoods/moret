const mathLib = artifacts.require('./FullMath');

module.exports = (deployer) => deployer
    .then(() => deployFullMath(deployer))
    .then(() => displayDeployed());

async function deployFullMath(deployer) {
    await deployer.deploy(mathLib);
}

async function displayDeployed() {
    const mathInstance = await mathLib.deployed();
    console.log(`=========
    Deployed FullMath: ${mathInstance.address}
    =========`)
}
