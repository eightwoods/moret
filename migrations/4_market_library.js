const optionLib = artifacts.require('./OptionLibrary');
const marketLib = artifacts.require('./MarketLibrary');

module.exports =(deployer) => deployer
  .then(()=> deployOptionLibrary(deployer))
  .then(()=> displayDeployed());

async function deployOptionLibrary(deployer){
  await deployer.link(optionLib, marketLib);
  await deployer.deploy(marketLib);
}

async function displayDeployed(){
  const marketLibInstance = await marketLib.deployed();
  console.log(`=========
    Deployed MarketLibrary: ${marketLibInstance.address}
    =========`)
}
