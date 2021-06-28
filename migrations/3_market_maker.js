const settings ={
  name: "Moret MATIC Market Pool",
  symbol: "MATICmp",
  chainLinkAddress: '0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada',
  stableCoinAddress: '0x2d7882beDcbfDDce29Ba99965dd3cdF7fcB10A1e',
  underlyingCoinAddress: '0x0000000000000000000000000000000000001010',
  swapRouterAddress: '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff ',
  isUnderlyingNative: true
};

const volChain = artifacts.require("./VolatilityChain");
const volToken = artifacts.require("./VolatilityToken");
const optionVault = artifacts.require('./OptionVault');
const marketMaker = artifacts.require('./MoretMarketMaker');
const exchange = artifacts.require('./MoretExchange');
const optionLib = artifacts.require('./OptionLibrary');

module.exports =(deployer, network, accounts) => deployer
  .then(()=> deployOptionLib(deployer))
  .then(()=> deployOptionVault(deployer))
  .then(()=> deployMarketMaker(deployer, accounts[0]))
  .then(()=> deployExchnage(deployer))
  .then(()=> displayMarketMaker());

async function deployOptionLib(deployer)
{
    await deployer.deploy(optionLib);
    return deployer.link(optionLib, [optionVault, marketMaker , exchange]);
}

async function deployOptionVault(deployer){
  const volChainInstance = (await volChain.deployed());
  return deployer.deploy(
    optionVault,
    settings.chainLinkAddress,
    volChainInstance.address
  );
}

async function deployMarketMaker(deployer, account){
  const optionVaultInstance = (await optionVault.deployed());

  return deployer.deploy(
    marketMaker,
    settings.name,
    settings.symbol,
    settings.underlyingCoinAddress,
    optionVaultInstance.address,
    settings.isUnderlyingNative,
    {from: account, value: 50 * 10 ** 15}
  );
}

async function deployExchange(deployer){
  const optionVaultInstance = (await optionVault.deployed());
  const marketMakerInstance = (await marketMaker.deployed());
  const volTokenInstance = (await volToken.deployed());

return deployer.deploy(
    exchange,
    marketMakerInstance.addres,
    optionContractInstance.address,
    volTokenInstance.address
  );
}

// async function assignAdmin(owner){
//   const marketMakerInstance = (await marketMaker.deployed());
//   marketMaker.grantRole(marketMaker.ADMIN_ROLE, owner);
// }
//
// async function addTenor(){
//   const marketMakerInstance = (await marketMaker.deployed());
//   marketMaker.addVolToken(settings.volToken);
//   console.log(`=========
//     Vol Token added: ${settings.volToken}
//     =========`)
// }

async function displayMarketMaker(){
  const marketMakerInstance = (await marketMaker.deployed());
  console.log(`=========
    Deployed MarketMaker: ${marketMaker.address}
    =========`)
}
