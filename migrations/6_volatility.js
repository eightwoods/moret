const parameterDecimals = 8;  
const settings={
  one: {ext: '1', seconds: 86400,  params: [4700000,20000000,0,0,90000000,10000000]},
  seven: { ext: '7', seconds: 604800,  params: [13228756, 52915026 ,0,0,90000000,10000000]},
  thirty: { ext: '30', seconds: 2592000,  params: [27386127, 109544511 ,0,0,90000000,10000000]}};

const volChain = artifacts.require("./VolatilityChain");
const volToken = artifacts.require("./VolatilityToken");
const mathLib = artifacts.require('./MathLib');
const marketLib = artifacts.require('./MarketLib');
const exchange = artifacts.require('./Exchange');

module.exports = (deployer) => deployer
  // .then(()=> deployVolChain(deployer))
  .then(() => deployVolToken(deployer))
  .then(() => displayDeployed());

async function deployVolChain(deployer){
  await deployer.link(mathLib, volChain);
  await deployer.deploy(
    volChain,
    process.env.CHAINLINK_FEED,
    parameterDecimals,
    process.env.TOKEN_NAME,
    process.env.RELAY_ACCOUNT
  );
}

async function deployVolToken(deployer) {
  var exchangeInstance = await exchange.deployed();
  await deployer.link(mathLib, volToken);
  await deployer.link(marketLib, volToken);

  await deployer.deploy(
    volToken,
    process.env.STABLE_COIN_ADDRESS,
    process.env.TOKEN_ADDRESS,
    settings.one.seconds,
    [process.env.TOKEN_NAME, settings.one.ext, 'day'].join(' '),
    [process.env.TOKEN_NAME, settings.one.ext].join(''),
    exchangeInstance.address
  );
}

async function displayDeployed(){
  // const varChainInstance = await volChain.deployed();
  const varTokenInstance = await volToken.deployed();
  
  // await varChainInstance.resetVolParams(settings.one.seconds, settings.one.params);
  // await varChainInstance.resetVolParams(settings.seven.seconds, settings.seven.params);
  // await varChainInstance.resetVolParams(settings.thirty.seconds, settings.thirty.params);
  
  console.log(`=========
    Deployed VolatilityToken: ${varTokenInstance.address}
    =========`)
}
