const settings={
  parameterDecimals: 8,    
  secondsPer1D: 86400, 
  params: [5000000,20000000,0,0,90000000,10000000]
  };

const volChain = artifacts.require("./VolatilityChain");
const volToken = artifacts.require("./VolatilityToken");

module.exports = (deployer) => deployer
  .then(()=> deployVolChain(deployer))
  .then(()=> deployVolToken(deployer))
  .then(()=> displayDeployed());

async function deployVolChain(deployer){
  await deployer.deploy(
    volChain,
    process.env.CHAINLINK_FEED,
    settings.parameterDecimals,
    process.env.TOKEN_NAME
  );
  let varChainInstance = await volChain.deployed();
  await varChainInstance.resetVolParams(settings.secondsPer1D, settings.params);
}

async function deployVolToken(deployer){
  await deployer.deploy(
    volToken,
    process.env.TOKEN_NAME,
    settings.secondsPer1D,
    [settings.tokenName, "1D", "Volatility"].join(' '),
    settings.tokenName + "1"
  );
}

async function displayDeployed(){
  const varChainInstance = await volChain.deployed();
  const volTokenInstance = await volToken.deployed();
  console.log(`=========
    Deployed VolChain: ${varChainInstance.address}
    Deployed VolToken: ${volTokenInstance.address}
    =========`)
}
