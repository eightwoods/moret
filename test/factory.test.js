const { assert } = require("chai");

const one = { ext: '1', seconds: 86400, 'params': [5234240, 5234240,0,0,90000000,10000000]};
const seven = { ext: '7', seconds: 604800, 'params': [13848496, 13848496 ,0,0,90000000,10000000]};
const thirty = { ext: '30', seconds: 2592000, 'params': [28669109, 28669109 ,0,0,90000000,10000000]};

const ERC20 = artifacts.require("./ERC20");

const VolatilityChain = artifacts.require("./VolatilityChain");
const VolatilityToken = artifacts.require("./VolatilityToken");
const Moret = artifacts.require('./Moret');
const MoretBroker = artifacts.require('./MoretBroker');
const Govern = artifacts.require('./Govern');

const MarketMakerFactory = artifacts.require('./MarketMakerFactory');
const PoolFactory = artifacts.require('./PoolFactory');
const PoolGovernorFactory = artifacts.require('./PoolGovernorFactory');
// const timelockController = artifacts.require('./TimelockController');

const MarketMaker = artifacts.require('./MarketMaker');
const Pool = artifacts.require('./Pool');

const Exchange = artifacts.require('./Exchange');
const OptionVault = artifacts.require('./OptionVault');


const initialCapital = 1;
const optionAmount = 1e16;
let token_address = web3.utils.toChecksumAddress(process.env.TOKEN_ADDRESS);

contract("Factory test", async accounts => {
    it("add hedging bot", async () => {
        const account_one = accounts[0];
        const moretInstance = await Moret.deployed();
        await moretInstance.updateEligibleRoute(web3.utils.toChecksumAddress(process.env.ONEINCH_ROUTE), true, { from: account_one });
    })

    it("Add volchain to Moret", async () => {
        const account_one = accounts[0];

        const moretInstance = await Moret.deployed();
        // const volChainInstance = await VolatilityChain.deployed();
        // const volChainInstance = await VolatilityChain.new(web3.utils.toChecksumAddress(process.env.CHAINLINK_FEED), 8, process.env.TOKEN_NAME, web3.utils.toChecksumAddress(process.env.RELAY_ACCOUNT));
        // await volChainInstance.resetVolParams(one.seconds, one.params);
        // await volChainInstance.resetVolParams(seven.seconds, seven.params);
        // await volChainInstance.resetVolParams(thirty.seconds, thirty.params);

        await moretInstance.updateVolChain(token_address, volChainInstance.address, { from: account_one});
        var outVolChain = await moretInstance.getVolatilityChain(token_address);
        assert.equal(outVolChain, volChainInstance.address, 'vol chain not deployed correctly');

        var outVol = await volChainInstance.queryVol(one.seconds);
        assert.equal(web3.utils.fromWei(outVol), 0.047, 'wrong atm vol');
    });

    it("Add vol token to Moret", async () => {
        const account_one = accounts[0];

        const moretInstance = await Moret.deployed();
        
        // const volTokenInstance = await VolatilityToken.deployed();
        // await moretInstance.updateVolToken(token_address, one.seconds, volTokenInstance.address, { from: account_one });
        // var outVolToken = await moretInstance.getVolatilityToken(token_address, one.seconds);
        // assert.equal(outVolToken, volTokenInstance.address, 'vol token not deployed correctly');
    
        // var outAddress = await volTokenInstance.underlying();
        // assert.equal(outAddress, token_address, 'wrong underlying');

        // add 1d, 7d and 30d vol tokens
        var exchangeInstance = await Exchange.deployed();
        // await deployer.link(mathLib, volToken);
        var volToken = await VolatilityToken.new(process.env.STABLE_COIN_ADDRESS, token_address, one.seconds, [process.env.TOKEN_NAME, one.ext, 'days'].join(' '), [process.env.TOKEN_NAME, one.ext].join(''), exchangeInstance.address);
        await moretInstance.updateVolToken(token_address, one.seconds, volToken.address, { from: account_one });
        outVolToken = await moretInstance.getVolatilityToken(token_address, one.seconds);
        assert.equal(outVolToken, volToken.address, '1d vol token not deployed correctly')

        volToken = await VolatilityToken.new(process.env.STABLE_COIN_ADDRESS, token_address, seven.seconds, [process.env.TOKEN_NAME, seven.ext, 'days'].join(' '), [process.env.TOKEN_NAME, seven.ext].join(''), exchangeInstance.address);
        await moretInstance.updateVolToken(token_address, seven.seconds, volToken.address, {from: account_one} );
        outVolToken = await moretInstance.getVolatilityToken(token_address, seven.seconds);
        assert.equal(outVolToken, volToken.address, '7d vol token not deployed correctly')

        volToken = await VolatilityToken.new(process.env.STABLE_COIN_ADDRESS, token_address, thirty.seconds, [process.env.TOKEN_NAME, thirty.ext, 'days'].join(' '), [process.env.TOKEN_NAME, thirty.ext].join(''), exchangeInstance.address);
        await moretInstance.updateVolToken(token_address, thirty.seconds, volToken.address, {from: account_one});
        outVolToken = await moretInstance.getVolatilityToken(token_address, thirty.seconds);
        assert.equal(outVolToken, volToken.address, '30d vol token not deployed correctly')
    });

    it("create Pool and buy option", async () => {
        const account_one = accounts[0];

        const marketFactoryInstance = await MarketMakerFactory.deployed();
        const poolFactoryInstance = await PoolFactory.deployed();
        const poolGovFactoryInstance = await PoolGovernorFactory.deployed();
        // const timelockInstance = await timelockController.deployed();
        const brokerInstance = await MoretBroker.deployed();
        const exchangeInstance = await Exchange.deployed();
        const vaultInstance = await OptionVault.deployed();
        // const moretInstance = await Moret.deployed();

        let factoryCount = await marketFactoryInstance.count();
        let salt = web3.utils.keccak256(factoryCount.toString());
        let marketMakerDescription = web3.utils.fromAscii('MarketMaker ' + process.env.TOKEN_NAME);
        await marketFactoryInstance.deploy(salt, web3.utils.toChecksumAddress(process.env.RELAY_ACCOUNT), token_address, marketMakerDescription, {from: account_one});
        let marketAddress = await marketFactoryInstance.computeAddress(salt, web3.utils.toChecksumAddress(process.env.RELAY_ACCOUNT), token_address, marketMakerDescription);
        let market = await MarketMaker.at(marketAddress);
        let outHedgingCost = await market.hedgingCost();
        assert.equal(web3.utils.fromWei(outHedgingCost), 0.003, 'wrong MarketMaker fees');

        let poolName = process.env.TOKEN_NAME + ' Pool';
        let poolSymbol = process.env.TOKEN_NAME + 'mp';

        await poolFactoryInstance.deploy(salt, poolName, poolSymbol, marketAddress, brokerInstance.address, { from: account_one });
        let poolAddress = await poolFactoryInstance.computeAddress(salt, poolName, poolSymbol, marketAddress);
        let pool = await Pool.at(poolAddress);
        let outExerciseFee = await pool.exerciseFee();
        assert.equal(web3.utils.fromWei(outExerciseFee), 0.01, 'wrong Pool fees');

        await poolGovFactoryInstance.deploy(salt, poolAddress, {from: account_one});
        let poolGovBytecode = web3.utils.soliditySha3(Govern.bytecode, web3.eth.abi.encodeParameters(['address'], [poolAddress]));
        let poolGovAddress = '0x' + web3.utils.soliditySha3('0xff', poolGovFactoryInstance.address, salt, poolGovBytecode).substr(26);
        let poolGovInstance = await Govern.at(poolGovAddress);
        // const outName = await poolGovInstance.name();
        // assert.equal(outName, poolGovName, 'wrong Pool name'); 
        
        const fundingAddress = await market.funding();
        const funding = await ERC20.at(fundingAddress);
        const fundingDecimals = await funding.decimals();
        var initialCapitalERC20 = 1 * (10 ** (Number(fundingDecimals)));
        initialCapitalERC20 = web3.utils.toBN(initialCapitalERC20.toString());
        // await funding.approve(exchangeInstance.address, process.env.MAX_AMOUNT, {from: account_one});
        await exchangeInstance.addCapital(poolAddress, initialCapitalERC20, { from: account_one });
        // await exchangeInstance.withdrawCapital(poolAddress, balanceToWithdraw, {from: account_one});
        let poolCapital = await vaultInstance.calcCapital(poolAddress, false, false);
        assert.equal(web3.utils.fromWei(poolCapital), initialCapital, 'wrong capital invested');

        const moretInstance = await Moret.deployed();
        await moretInstance.updateVolTradingPool(poolAddress, true, { from: account_one });

    });

    it("add options", async()=>{
        const account_one = accounts[0];

        const brokerInstance = await MoretBroker.deployed();
        const exchangeInstance = await Exchange.deployed();
        const vaultInstance = await OptionVault.deployed();

        const pools = await brokerInstance.getAllPools(token_address);
        assert.equal(pools.length, 1, 'incorrect number of pools');

        const pool = await Pool.at(pools[0]);
        const optionQuote = await exchangeInstance.queryOption(pool.address, one.seconds, 1, web3.utils.toBN(optionAmount), 1, 0, true);

        // const volchainInstance = await VolatilityChain.deployed();
        // const spotPrice = await volchainInstance.queryPrice();
        // const delta = await vaultInstance.calculateAggregateDelta(pool.address, spotPrice, false);

        // assert.equal(parseFloat(web3.utils.fromWei(optionQuote[0])).toFixed(2), '0.39', 'option price wrong');
        assert.equal(parseFloat(web3.utils.fromWei(optionQuote[1])), 0, 'option collateral wrong');
        
        const volchainAddress = await moret.methods.getVolatilityChain(tokenAddress).call();
        assert.equal(parseFloat(web3.utils.fromWei(optionQuote[3])).toFixed(2), '0.90', 'option vol wrong');

        const marketAddress = await pool.marketMaker();
        const market = await MarketMaker.at(marketAddress);
        const fundingAddress = await market.funding();
        const funding = await ERC20.at(fundingAddress);
        
        const optionCost = parseFloat(web3.utils.fromWei(optionQuote[0])) * 1.5 + parseFloat(web3.utils.fromWei(optionQuote[1])) * 1.1;
        await funding.approve(exchangeInstance.address, web3.utils.toWei(optionCost.toString()), { from: account_one });

        await exchangeInstance.tradeOption(pool.address, one.seconds, optionQuote[2], web3.utils.toBN(optionAmount), 1, 0);
        const optionCount = await vaultInstance.getActiveOptionCount(pool.address);
        assert.equal(optionCount.toNumber(), 1, 'incorrect option count');

        const option = await vaultInstance.getOption(0);
        assert.equal(parseInt(option['tenor']), one.seconds, 'incorrect option contract');
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



