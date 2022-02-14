const volDecimals = 6;
const tenor = 1;
const settings = { seconds: 86400 * tenor, tenor: String(tenor)};

const exchange = artifacts.require('./Exchange');
const volToken = artifacts.require('./VolatilityToken');

module.exports = (deployer) => deployer
    .then(() => deployVolTokens(deployer))
    .then(() => displayDeployed());

async function deployVolTokens(deployer) {
    var exchangeInstance = await exchange.deployed();
    
    await deployer.deploy(
        volToken,
        process.env.TOKEN_NAME,
        settings.seconds,
        process.env.TOKEN_NAME + ' ' + settings.tenor + 'D Volatility',
        process.env.TOKEN_NAME + settings.tenor,
        exchangeInstance.address
    );
}

async function displayDeployed() {
    var volTokenInstance = await volToken.deployed();
    var exchangeInstance = await exchange.deployed();

    await exchangeInstance.addVolToken(settings.seconds, volTokenInstance.address);

    console.log(`=========
    Deployed VolToken: ${volTokenInstance.address}
    =========`);
}