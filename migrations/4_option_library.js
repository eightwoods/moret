const optionLib = artifacts.require('./OptionLibrary');
const mathLib = artifacts.require('./FullMath');

module.exports =(deployer) => deployer
  .then(()=> deployOptionLibrary(deployer))
  .then(()=> displayDeployed());

async function deployOptionLibrary(deployer) {
  await deployer.link(mathLib, optionLib);
  await deployer.deploy(optionLib);
}

async function displayDeployed(){
  const optionLibInstance = await optionLib.deployed();
  console.log(`=========
    Deployed OptionLibrary: ${optionLibInstance.address}
    =========`)
}
