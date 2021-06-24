const settings ={
  marketName: "Moret MATIC Market Pool",
  tokenName: "MATICmp",
  chainLinkAddress: '0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada',
  moretTokenAddress: '0xaaebF0f601355831a64823A89AbdFF6f1e43D592',
  isUnderlyingNative: true,
  volToken: '0xd01C2B48f039Cc8537f39541D28d313c87c79bbe'
};

const volChain = artifacts.require("./VolatilityChain");
const marketMaker = artifacts.require('./MarketMaker');

module.exports =(deployer, network, accounts) => deployer
  .then(()=> deployMarketMaker(deployer))
  // .then(()=> assignAdmin(accounts[0]))
  // .then(()=> addTenor())
  .then(()=> displayMarketMaker());

function deployMarketMaker(deployer){
  return deployer.deploy(
    marketMaker,
    settings.marketName,
    settings.tokenName,
    settings.chainLinkAddress,
    settings.moretTokenAddress,
    '0xf425f1274A20E801B9Bd8e6dF6414F0e337d5fba',
    settings.isUnderlyingNative,
    {value: 50 * 10 ** 15}
  );
}

// async function assignAdmin(owner){
//   const marketMakerInstance = (await marketMaker.deployed());
//   marketMaker.grantRole(marketMaker.ADMIN_ROLE, owner);
// }

async function addTenor(){
  const marketMakerInstance = (await marketMaker.deployed());
  marketMaker.addVolToken(settings.volToken);
  console.log(`=========
    Vol Token added: ${settings.volToken}
    =========`)
}

async function displayMarketMaker(){
  const marketMakerInstance = (await marketMaker.deployed());
  console.log(`=========
    Deployed MarketMaker: ${marketMaker.address}
    =========`)
}
