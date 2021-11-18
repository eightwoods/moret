const optionLib = artifacts.require('./OptionLibrary');
const marketLib = artifacts.require('./MarketLibrary');

module.exports =(deployer) => deployer
  .then(()=> deployOptionLibrary(deployer))
  .then(()=> displayDeployed());

async function deployOptionLibrary(deployer){
  await deployer.deploy(optionLib);

  await deployer.link(optionLib, marketLib);
  await deployer.deploy(marketLib);
}

async function displayDeployed(){
  const optionLibInstance = await optionLib.deployed();
  const marketLibInstance = await marketLib.deployed();
  console.log(`=========
    Deployed OptionLibrary: ${optionLibInstance.address}
    Deployed MarketLibrary: ${marketLibInstance.address}
    =========`)
}
