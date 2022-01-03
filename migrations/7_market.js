const initialCapital = 10 ** 5; // 6 decials for usdc on polygon 

const marketMaker = artifacts.require('./MoretMarketMaker');
const optionLib = artifacts.require('./OptionLibrary');
const marketLib = artifacts.require('./MarketLibrary');
const mathLib = artifacts.require('./FullMath');
const optionVault = artifacts.require("./OptionVault");
const ierc20 = artifacts.require("./IERC20");

module.exports = (deployer) => deployer
    .then(() => deployMarketMaker(deployer))
    .then(() => displayDeployed());

async function deployMarketMaker(deployer) {
    await deployer.link(mathLib, marketMaker);
    await deployer.link(optionLib, marketMaker);
    await deployer.link(marketLib, marketMaker);
    var optionVaultInstance = await optionVault.deployed();
    await deployer.deploy(
        marketMaker,
        ['Moret', process.env.TOKEN_NAME, 'Market Pool'].join(' '),
        process.env.TOKEN_NAME + 'mp',
        optionVaultInstance.address
    );
}

async function displayDeployed() {
    const marketMakerInstance = await marketMaker.deployed();
    let fundingContract = await ierc20.at(process.env.STABLE_COIN_ADDRESS);
    fundingContract.transfer(marketMakerInstance.address, initialCapital);

    var optionVaultInstance = await optionVault.deployed();
    var optionRole = await optionVaultInstance.EXCHANGE_ROLE();
    await optionVaultInstance.grantRole(optionRole, marketMakerInstance.address);

    var marketRole = await marketMakerInstance.EXCHANGE_ROLE();
    await marketMakerInstance.grantRole(marketRole, process.env.MINER_ADDRESS);

    // var role = await marketMakerInstance.ADMIN_ROLE();
    // console.log(role);
    // await marketMakerInstance.grantRole(role, process.env.RELAY_ACCOUNT);
    console.log(`=========
    Deployed MarketMaker: ${marketMakerInstance.address}
    =========`);
}