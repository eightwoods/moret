
const marketMaker = artifacts.require('./MoretMarketMaker');
const marketLib = artifacts.require('./MarketLibrary');
const optionVault = artifacts.require("./OptionVault");

module.exports = (deployer) => deployer
    .then(() => deployMarketMaker(deployer))
    .then(() => displayDeployed());


async function deployMarketMaker(deployer) {
    await deployer.deploy(marketLib);
    await deployer.link(marketLib, marketMaker);

    var optionVaultInstance = await optionVault.deployed();
    await deployer.deploy(
        marketMaker,
        ['Moret', process.env.TOKEN_NAME, 'Market Pool'].join(' '),
        process.env.TOKEN_NAME + 'mp',
        process.env.TOKEN_ADDRESS,
        process.env.STABLE_COIN_ADDRESS,
        optionVaultInstance.address,
        process.env.SWAP_ROUTER,
        process.env.AAVE_ADDRESS_PROVIDER,
        process.env.AAVE_DATA_PROVIDER
    );
}

async function displayDeployed() {
    const marketMakerInstance = await marketMaker.deployed();
    var role = await marketMakerInstance.ADMIN_ROLE();
    console.log(role);
    await marketMakerInstance.grantRole(role, process.env.RELAY_ACCOUNT);
    console.log(`=========
    Deployed MarketMaker: ${marketMakerInstance.address}
    =========`);
}