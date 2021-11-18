
const volChain = artifacts.require("./VolatilityChain");
const optionVault = artifacts.require("./OptionVault");
const optionLib = artifacts.require('./OptionLibrary');

module.exports =(deployer) => deployer
  .then(()=> deployOptionVault(deployer))
  .then(()=> displayDeployed());

async function deployOptionVault(deployer){
  await deployer.link(optionLib, optionVault);
  const varChainInstance = await volChain.deployed();
  await deployer.deploy(
    optionVault,
    varChainInstance.address
  );
}

async function displayDeployed(){
  const optionVaultInstance = await optionVault.deployed();
  console.log(`=========
    Deployed OptionVault: ${optionVaultInstance.address}
    =========`)
}
