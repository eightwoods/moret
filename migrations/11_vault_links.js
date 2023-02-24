const fip = artifacts.require('./FixedIndex');
const perp = artifacts.require('./Perp');

const optionLib = artifacts.require('./OptionLib');
const mathLib = artifacts.require('./MathLib');
const marketLib = artifacts.require('./MarketLib');


module.exports = (deployer) => deployer
    .then(() => linkLibraries(deployer));

async function linkLibraries(deployer) {
    await deployer.link(mathLib, fip);
    await deployer.link(optionLib, fip);
    await deployer.link(marketLib, fip);

    await deployer.link(mathLib, perp);
    await deployer.link(optionLib, perp);
    await deployer.link(marketLib, perp);
}


