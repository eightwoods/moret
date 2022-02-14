const parameterDecimals = 8;   
const settings={
  one: {seconds: 86400,  params: [4700000,20000000,0,0,90000000,10000000]},
  seven: {seconds: 604800,  params: [13228756, 52915026 ,0,0,90000000,10000000]},
  thirty: {seconds: 2592000,  params: [27386127, 109544511 ,0,0,90000000,10000000]}};

const volChain = artifacts.require("./VolatilityChain");
const mathLib = artifacts.require('./FullMath');

module.exports = (deployer) => deployer
    .then(()=> deployVolChain(deployer))
    .then(() => displayDeployed());

async function deployVolChain(deployer){
  await deployer.link(mathLib, volChain);
  await deployer.deploy(
    volChain,
    process.env.CHAINLINK_FEED,
    parameterDecimals,
    process.env.TOKEN_NAME
  );
}

async function displayDeployed(){
  const varChainInstance = await volChain.deployed();
  var updateRole = await varChainInstance.UPDATE_ROLE();
  await varChainInstance.grantRole(updateRole, process.env.RELAY_ACCOUNT);

  await varChainInstance.resetVolParams(settings.one.seconds, settings.one.params);
  await varChainInstance.resetVolParams(settings.seven.seconds, settings.seven.params);
  await varChainInstance.resetVolParams(settings.thirty.seconds, settings.thirty.params);
  
  console.log(`=========
    Deployed VolChain: ${varChainInstance.address}
    =========`)
}
