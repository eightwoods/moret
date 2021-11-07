const parameterDecimals = 8;   
const settings={
  one: {seconds: 86400,  params: [5000000,20000000,0,0,90000000,10000000]},
  seven: {seconds: 604800,  params: [13228756, 52915026 ,0,0,90000000,10000000]},
  thirty: {seconds: 2592000,  params: [27386127, 109544511 ,0,0,90000000,10000000]}};

const volChain = artifacts.require("./VolatilityChain");
// const volToken = artifacts.require("./VolatilityToken");

module.exports = (deployer) => deployer
    .then(()=> deployVolChain(deployer))
    // .then(()=> deployVolToken(deployer))
    .then(() => displayDeployed());

async function deployVolChain(deployer){
  await deployer.deploy(
    volChain,
    process.env.CHAINLINK_FEED,
    parameterDecimals,
    process.env.TOKEN_NAME
  );
  let varChainInstance = await volChain.deployed();
  await varChainInstance.resetVolParams(settings.one.seconds, settings.one.params);
  await varChainInstance.resetVolParams(settings.seven.seconds, settings.seven.params);
  await varChainInstance.resetVolParams(settings.thirty.seconds, settings.thirty.params);
  assignRoles(varChainInstance);
}

/* async function deployVolToken(deployer){
  await deployer.deploy(
    volToken,
    process.env.TOKEN_NAME,
    settings.secondsPer1D,
    [settings.tokenName, "1D", "Volatility"].join(' '),
    settings.tokenName + "1"
  );
} */

async function assignRoles(varChainInstance) {
  await varChainInstance.grantRole(varChainInstance.UPDATE_ROLE, process.env.RELAY_ACCOUNT);
}

async function displayDeployed(){
  const varChainInstance = await volChain.deployed();
  // const volTokenInstance = await volToken.deployed();
  console.log(`=========
    Deployed VolChain: ${varChainInstance.address}
    =========`)
}
