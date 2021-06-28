const settings={
    priceSourceId: '0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada',
    parameterDecimals: 8,
    tokenName: "MATIC",
    tenor: 86400,
    params: [5000000,20000000,0,0,90000000,10000000],
    underlying: 'MATIC / USD',
    volName: "MATIC 1d Volatility",
    volSymbol: "MATIC1"
    };

const volChain = artifacts.require("./VolatilityChain");
const volToken = artifacts.require("./VolatilityToken");

module.exports = (deployer, network, accounts) => deployer
  .then(()=> deployVolChain(deployer))
  .then(()=> setVolChain())
  .then(()=> deployVolToken(deployer))
  .then(()=> displayVolChain());

function deployVolChain(deployer){
  return deployer.deploy(
    volChain,
    settings.priceSourceId,
    settings.parameterDecimals,
    settings.tokenName
  );}


function deployVolToken(deployer){
  return deployer.deploy(
    volToken,
    settings.underlying,
    settings.tenor,
    settings.volName,
    settings.volSymbol
  );
}

async function setVolChain(){
  const varChainInstance = (await volChain.deployed());
  varChainInstance.resetVolParams(settings.tenor, settings.params);
}

async function displayVolChain(){
  const varChainInstance = (await volChain.deployed());
  const volTokenInstance = (await volToken.deployed());
  console.log(`=========
    Deployed VolChain: ${volChain.address}
    Deployed VolToken: ${volToken.address}
    =========`)
}
