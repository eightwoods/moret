// const { assert } = require("chai");

const { assert } = require("chai");

const ERC20 = artifacts.require("./ERC20");

const VolatilityChain = artifacts.require("./VolatilityChain");
const VolatilityToken = artifacts.require("./VolatilityToken");
const Moret = artifacts.require('./Moret');
const MoretBroker = artifacts.require('./MoretBroker');

const MarketMakerFactory = artifacts.require('./MarketMakerFactory');
const PoolFactory = artifacts.require('./PoolFactory');
const PoolGovernorFactory = artifacts.require('./PoolGovernorFactory');
// const timelockController = artifacts.require('./TimelockController');

const MarketMaker = artifacts.require('./MarketMaker');
const Pool = artifacts.require('./Pool');

const Exchange = artifacts.require('./Exchange');
const OptionVault = artifacts.require('./OptionVault');

const tenor = 86400;
const marketMakerDescription = web3.utils.fromAscii('test MarketMaker maker');
const poolName = 'ETH Market Pool Test';
const poolSymbol = 'ETHmpTest';
const initialCapital = 1e18;
const optionAmount = 1e16;
const optionApproveAmount = 1e6;
const token_address = web3.utils.toChecksumAddress(process.env.TOKEN_ADDRESS);
const relay_address = web3.utils.toChecksumAddress(process.env.RELAY_ACCOUNT);

contract("Factory test", async accounts => {
    it("Add volchain to Moret", async () => {
        const account_one = accounts[0];

        const moretInstance = await Moret.deployed();
        const volChainInstance = await VolatilityChain.deployed();

        await moretInstance.updateVolChain(token_address, volChainInstance.address, { from: account_one});
        var outVolChain = await moretInstance.getVolatilityChain(token_address);
        assert.equal(outVolChain, volChainInstance.address, 'vol chain not deployed correctly');

        var outVol = await volChainInstance.queryVol(tenor);
        assert.equal(web3.utils.fromWei(outVol), 0.047, 'wrong atm vol');
    });

    it("Add vol token to Moret", async () => {
        const account_one = accounts[0];

        const moretInstance = await Moret.deployed();
        const volTokenInstance = await VolatilityToken.deployed();

        await moretInstance.updateVolToken(token_address, tenor, volTokenInstance.address, { from: account_one });
        var outVolToken = await moretInstance.getVolatilityToken(token_address, tenor);
        assert.equal(outVolToken, volTokenInstance.address, 'vol token not deployed correctly');
    
        var outAddress = await volTokenInstance.underlying();
        assert.equal(outAddress, process.env.TOKEN_ADDRESS, 'wrong underlying');
    });

    it("create Pool and buy option", async () => {
        const account_one = accounts[0];
        const hedging_bot = account_one;

        const marketFactoryInstance = await MarketMakerFactory.deployed();
        const poolFactoryInstance = await PoolFactory.deployed();
        const poolGovFactoryInstance = await PoolGovernorFactory.deployed();
        // const timelockInstance = await timelockController.deployed();
        const brokerInstance = await MoretBroker.deployed();
        const exchangeInstance = await Exchange.deployed();
        const vaultInstance = await OptionVault.deployed();
        // const moretInstance = await Moret.deployed();

        const factoryCount = await marketFactoryInstance.count();
        const salt = web3.utils.keccak256(factoryCount.toString());
        await marketFactoryInstance.deploy(salt, hedging_bot, token_address, marketMakerDescription, {from: account_one});
        const marketAddress = await marketFactoryInstance.computeAddress(salt, hedging_bot, token_address, marketMakerDescription);
        const marketInstance = await MarketMaker.at(marketAddress);
        const outHedgingCost = await marketInstance.hedgingCost();
        assert.equal(web3.utils.fromWei(outHedgingCost), 0.003, 'wrong MarketMaker fees');

        await poolFactoryInstance.deploy(salt, poolName, poolSymbol, marketAddress, brokerInstance.address, { from: account_one });
        const poolAddress = await poolFactoryInstance.computeAddress(salt, poolName, poolSymbol, marketAddress);
        const poolInstance = await Pool.at(poolAddress);
        const outExerciseFee = await poolInstance.exerciseFee();
        assert.equal(web3.utils.fromWei(outExerciseFee), 0.005, 'wrong Pool fees');

        // const poolGovBytecode = web3.utils.soliditySha3(poolGovernor.bytecode, web3.eth.abi.encodeParameters(['address', 'address payable'], [poolInstance.address, timelockInstance.address]));

        // const poolGovAddress = await poolGovFactoryInstance.deploy(salt, poolGovBytecode, {from: account_one});
        // const poolGovInstance = await poolGovernor.at(poolGovAddress);
        // const outName = await poolGovInstance.name();
        // assert.equal(outName, poolGovName, 'wrong Pool name'); 
        
        const fundingAddress = await marketInstance.funding();
        const funding = await ERC20.at(fundingAddress);
        await funding.approve(exchangeInstance.address, web3.utils.toBN(initialCapital), {from: account_one});
        await exchangeInstance.addCapital(poolInstance.address, web3.utils.toBN(initialCapital), { from: account_one });
        const poolCapital = await vaultInstance.calcCapital(poolInstance.address, false, false);
        assert.equal(web3.utils.fromWei(poolCapital), web3.utils.fromWei(web3.utils.toBN(initialCapital)), 'wrong capital invested');

    });

    it("add options", async()=>{
        const account_one = accounts[0];

        const brokerInstance = await MoretBroker.deployed();
        const exchangeInstance = await Exchange.deployed();
        const vaultInstance = await OptionVault.deployed();

        const pools = await brokerInstance.getAllPools(token_address);
        assert.equal(pools.length, 1, 'incorrect number of pools');

        const poolInstance = await Pool.at(pools[0]);

        const optionQuote = await exchangeInstance.queryOption(poolInstance.address, tenor, 1, web3.utils.toBN(optionAmount), 1, 0, true);
        
        assert.equal(parseFloat(web3.utils.fromWei(optionQuote[0])).toFixed(2), '0.39', 'option price wrong');
        assert.equal(parseFloat(web3.utils.fromWei(optionQuote[1])), 0, 'option collateral wrong');
        assert.equal(parseFloat(web3.utils.fromWei(optionQuote[3])).toFixed(2), '0.90', 'option vol wrong');

        const marketAddress = await poolInstance.marketMaker();
        const marketInstance = await MarketMaker.at(marketAddress);
        const fundingAddress = await marketInstance.funding();
        const funding = await ERC20.at(fundingAddress);
        
        const optionCost = parseFloat(web3.utils.fromWei(optionQuote[0])) * 1.5 + parseFloat(web3.utils.fromWei(optionQuote[1])) * 1.1;
        await funding.approve(exchangeInstance.address, web3.utils.toWei(optionCost.toString()), { from: account_one });

        await exchangeInstance.tradeOption(poolInstance.address, tenor, optionQuote[2], web3.utils.toBN(optionAmount), 1, 0);
        const optionCount = await vaultInstance.getActiveOptionCount(poolInstance.address);
        assert.equal(optionCount.toNumber(), 1, 'incorrect option count');

        const option = await vaultInstance.getOption(0);
        assert.equal(parseInt(option['tenor']), tenor, 'incorrect option contract');
    })

    // it("check option info", async () => {
    //     const meta = await MetaCoin.deployed();
    //     const outCoinBalance = await meta.getBalance.call(accounts[0]);
    //     const metaCoinBalance = outCoinBalance.toNumber();
    //     const outCoinBalanceEth = await meta.getBalanceInEth.call(accounts[0]);
    //     const metaCoinEthBalance = outCoinBalanceEth.toNumber();
    //     assert.equal(metaCoinEthBalance, 2 * metaCoinBalance);
    // });

});



