const optionVault = artifacts.require("./OptionVault");

module.exports = (deployer, network, accounts) => deployer
    .then(() => deployOptionVault(deployer))
    .then(() => displayDeployed(accounts));


async function deployOptionVault(deployer) {
    await deployer.deploy(optionVault);
}

async function displayDeployed(accounts) {
    var optionVaultInstance = await optionVault.deployed();
    
    console.log(`=========
    Account: ${accounts[0]}
    Deployed OptionVault: ${optionVaultInstance.address}
    =========`);
}