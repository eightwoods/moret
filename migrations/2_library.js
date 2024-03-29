const optionLib = artifacts.require('./OptionLib');
const mathLib = artifacts.require('./MathLib');
const marketLib = artifacts.require('./MarketLib');

const exchange = artifacts.require('./Exchange');
const optionVault = artifacts.require("./OptionVault");
const moret = artifacts.require('./Moret');
const broker = artifacts.require('./MoretBroker');
const volChain = artifacts.require("./VolatilityChain");
const volToken = artifacts.require("./VolatilityToken");
const fip = artifacts.require('./FixedIncomeAnnuity');

module.exports =(deployer) => deployer
  .then(() => deployMathLibrary(deployer))
  .then(()=> deployOptionLibrary(deployer))
  .then(() => deployMarketLibrary(deployer))
  .then(()=> displayDeployed());

async function deployMathLibrary(deployer) {
  await deployer.deploy(mathLib);
}

async function deployOptionLibrary(deployer) {
  await deployer.link(mathLib, optionLib);
  await deployer.deploy(optionLib);
}

async function deployMarketLibrary(deployer) {
  await deployer.link(mathLib, marketLib);
  await deployer.link(optionLib, marketLib);
  await deployer.deploy(marketLib);
}

async function displayDeployed(){
  const mathLibInstance = await mathLib.deployed();
  const optionLibInstance = await optionLib.deployed();
  const marketLibInstance = await marketLib.deployed();
  console.log(`=========
    Deployed MathLibrary: ${mathLibInstance.address}
    Deployed OptionLibrary: ${optionLibInstance.address}
    Deployed MarketLibrary: ${marketLibInstance.address}
    =========`)
}
