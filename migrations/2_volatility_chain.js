const settings={
    priceSourceId: '0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada',
    parameterDecimals: 8,
    tokenName: "MATIC",
    tenor: 86400,
    params: [5000000,20000000,0,0,90000000,10000000]
    };

const volChain = artifacts.require("./VolatilityChain");

module.exports = (deployer) => deployer
  .then(()=> deployVolChain(deployer))
  .then(()=> setVolChain())
  .then(()=> displayVolChain());

function deployVolChain(deployer){
  return deployer.deploy(
    volChain,
    settings.priceSourceId,
    settings.parameterDecimals,
    settings.tokenName,
    {overwrite: true}
  );
}

async function setVolChain(){
  const varChainInstance = (await volChain.deployed());
  varChainInstance.resetVolParams(settings.tenor, settings.params);
}

async function displayVolChain(){
  const varChainInstance = (await volChain.deployed());
  console.log(`=========
    Deployed VolChain: ${volChain.address}
    =========`)
}
