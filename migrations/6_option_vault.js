
const volChain = artifacts.require("./VolatilityChain");
const optionLib = artifacts.require('./OptionLibrary');
const marketLib = artifacts.require('./MarketLibrary');
const mathLib = artifacts.require('./FullMath');
const optionVault = artifacts.require("./OptionVault");

module.exports =(deployer) => deployer
  .then(()=> deployOptionVault(deployer))
  .then(()=> displayDeployed());

async function deployOptionVault(deployer){
  await deployer.link(mathLib, optionVault);
  await deployer.link(optionLib, optionVault);
  await deployer.link(marketLib, optionVault);
  const varChainInstance = await volChain.deployed();;

  await deployer.deploy(
    optionVault,
    varChainInstance.address,
    process.env.TOKEN_ADDRESS,
    process.env.STABLE_COIN_ADDRESS,
    process.env.AAVE_ADDRESS_PROVIDER
  );
}

async function displayDeployed(){
  const optionVaultInstance = await optionVault.deployed();
  console.log(`=========
    Deployed OptionVault: ${optionVaultInstance.address}
    =========`)
}
