const optionLib = artifacts.require('./OptionLib');
const mathLib = artifacts.require('./MathLib');
const marketLib = artifacts.require('./MarketLib');

const exchange = artifacts.require('./Exchange');
const optionVault = artifacts.require("./OptionVault");
const moret = artifacts.require('./Moret');
const broker = artifacts.require('./MoretBroker');
const volChain = artifacts.require("./VolatilityChain");
const volToken = artifacts.require("./VolatilityToken");


module.exports = (deployer) => deployer
    .then(() => linkLibraries(deployer));

async function linkLibraries(deployer) {
    await deployer.link(mathLib, optionVault);
    await deployer.link(optionLib, optionVault);
    await deployer.link(marketLib, optionVault);

    await deployer.link(mathLib, exchange);
    // await deployer.link(optionLib, exchange);
    await deployer.link(marketLib, exchange);

    await deployer.link(mathLib, broker);
    await deployer.link(mathLib, moret);

    await deployer.link(mathLib, volChain);
    await deployer.link(mathLib, volToken);
    await deployer.link(marketLib, volToken);
}
