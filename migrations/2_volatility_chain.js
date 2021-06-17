const settings ={
  priceSourceId: 0x9326BFA02ADD2366b30bacB125260Af641031331,
  parameterDecimals: 8,
  tokenName: "ETH"
};

const volChain = artifacts.require("./VolatilityChain");

module.exports =(deployer, owner) => deployer.then(()=> deployVolChain(deployer, owner));

function deployVolChain(deployer, owner){
  return deployer.deploy(volChain,
    settings.priceSourceId,
    settings.parameterDecimals,
    settings.tokenName,
  );
}
