const { moretAddress, exchangeAddress, poolAddresses, tokenAddresses, aaveAddressesProvider, tokens, chainId, maxAmount, hedgeThreshold, oneinchUrl, oneinchSlippage, defaultGas, allowShorting, lendingPoolRateMode} = require('./config.json');
const { getDelta, getGamma, getVega, getTheta } = require('greeks');
const approveCheckAmount = 1000000;
const allowTrade = false;

const { DefenderRelayProvider } = require('defender-relay-client/lib/web3');
const Web3 = require('web3');

const credentials = { apiKey: process.env.RELAYER_KEY, apiSecret: process.env.RELAYER_SECRET };
const provider = new DefenderRelayProvider(credentials, { speed: 'fast' });
const web3 = new Web3(provider);

// return contract object based on abi file, address and account
function getContract(abiFile, address, account) {
    var { abi } = require('../build/contracts/' + abiFile);
    var contract = new web3.eth.Contract(abi, address, { from: account });
    return contract;
}

// return data in json format from url (for 1inch request)
async function fetchAsync(url) {
    let response = await fetch(url);
    let data = await response.json();
    return data;
}

// return data in json format from url with parameters (for 1inch request)
async function fetchAsyncWithParams(requestURL, params) {
    var url = new URL(requestURL);
    Object.keys(params).forEach(key => url.searchParams.append(key, params[key]))
    let response = await fetch(url);
    let data = await response.json();
    return data;
}

// async function loanPrincipal(address, isStable, account){
//     if(isStable){
//         let debt = getContract('IStableDebtToken.json', address, account);
//         let debtPrincipal = await debt.principalBalanceOf(account);
//         return debtPrincipal;
//     }
//     else{
//         let debt = getContract('IScaledBalanceToken.json', address, account);
//         let debtPrincipal = await debt.scaledBalanceOf(account);
//         return debtPrincipal;
//     }
// }

// async function loanBalance(address, account) {    
//     let debt = getContract('IERC20.json', address, account);
//     let debtBalance = await debt.balanceOf(account);
//     return parseFloat(web3.utils.fromWei(debtBalance));
// }

// Purchase underlying via 1inch
const buyUnderlying = async (market, funding, underlying, tradeHedge, spot, spenderAddress, fundingDecimals) => {
    var tradeValue = tradeHedge * spot;

    if (Math.abs(tradeValue) > hedgeThreshold) {
        let tradeFunding = web3.utils.toBN(web3.utils.toWei(tradeValue.toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(fundingDecimals))));
        let swapParams = { 'fromTokenAddress': funding._address, 'toTokenAddress': underlying._address, 'amount': Number(tradeFunding), 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
        swapData = await fetchAsyncWithParams(oneinchUrl + 'swap', swapParams);
        let callData = web3.utils.hexToBytes(swapData['tx']['data']);

        if (allowTrade) {
            await market.methods.trade(funding._address, maxAmount, spenderAddress, callData, defaultGas).send();
        }
        else {
            console.log(funding._address, Number(tradeFunding), spenderAddress, defaultGas);
        }
    }
}

// Sell underlying via 1Inch
const sellUnderlying = async (market, funding, underlying, tradeHedge, spot, spenderAddress, underlyingDecimals) => {
    var tradeValue = tradeHedge * spot;

    if (Math.abs(tradeValue) > hedgeThreshold) {
        let tradeUnderlying = web3.utils.toBN(web3.utils.toWei(Math.abs(tradeHedge).toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(underlyingDecimals))));
        let swapParams = { 'fromTokenAddress': underlying._address, 'toTokenAddress': funding._address, 'amount': Number(tradeUnderlying), 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
        swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
        let callData = web3.utils.hexToBytes(swapData['tx']['data']);

        if (allowTrade) {
            await market.methods.trade(underlying._address, maxAmount, spenderAddress, callData, defaultGas).send();
        }
        else {
            console.log(funding._address, Number(tradeFunding), spenderAddress, defaultGas);
        }
    }
}

// swap function adjust hedges of a given market maker contract address
// based on target hedge and current hedge positions, it calculates the following
// 1. buy underlying token
// 2. sell underlying token
const swap = async (market, funding, delta, spot, account) => {
    const underlyingAddress = await market.methods.underlying().call();
    const underlying = getContract('ERC20.json', underlyingAddress, account);
    const underlyingDecimals = await underlying.methods.decimals().call();
    const fundingDecimals = await funding.methods.decimals().call();

    let spenderData = await fetchAsync(oneinchUrl + "approve/spender");
    let spenderAddress = web3.utils.toChecksumAddress(spenderData['address']);
    // console.log('spender address', spenderAddress);

    let currentHedge = await underlying.methods.balanceOf(market._address).call();
    currentHedge = parseFloat(web3.utils.fromWei(web3.utils.toBN(currentHedge).mul(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(underlyingDecimals))))));
    const tradeHedge = delta - currentHedge;
    var tradeValue = tradeHedge * spot;
    console.log(delta, currentHedge, tradeHedge, tradeValue, hedgeThreshold, spot);

    if (tradeHedge > 0) {
        await buyUnderlying(market, funding, underlying, tradeHedge, spot, spenderAddress, fundingDecimals);
    }
    
    if (tradeHedge < 0){
        await sellUnderlying(market, funding, underlying, tradeHedge, spot, spenderAddress, underlyingDecimals);
    }
}

const hedge = async (vault, oracle, funding, pool, account, useContractFormula) => {
    let delta = 0.0;
    var spot = await oracle.methods.queryPrice().call();
    var spotPrice = parseFloat(web3.utils.fromWei(spot));

    if (useContractFormula){
        let aggDelta = await vault.methods.calculateAggregateDelta(pool._address, spot, false).call();
        delta = parseFloat(web3.utils.fromWei(aggDelta));
    }
    else{
        var ts = Math.round((new Date()).getTime() / 1000); // current UNIX timestamp in seconds
        
        const options = await vault.methods.getActiveOptions(pool._address).call();
        let deltas = new Map();;
        await Promise.all(options.map(async (optionId) => {
            let option = await vault.methods.getOption(optionId).call();
            let secondsToExpiry = Math.floor(option.maturity - ts);
            let timeToExpiry = secondsToExpiry / (3600*24*365);
            let optionStrike = parseFloat(web3.utils.fromWei(option.strike));
            let optionAmount = parseFloat(web3.utils.fromWei(option.amount));
            if (secondsToExpiry > 0){
                if (option.side == 0) { // buy options
                    let impliedVol = await oracle.methods.queryVol(secondsToExpiry).call();
                    let annualVol = parseFloat(web3.utils.fromWei(impliedVol)) / Math.sqrt(timeToExpiry);
                    deltas.set(optionId, getDelta(spotPrice, optionStrike, annualVol, 0, option.poType == 0 ? 'call' : 'put') * optionAmount);
                }
                else if (option.poType == 0){ // sell call options: delta = collateral = amount of ETH as notional
                    deltas.set(optionId, optionAmount);
                }
            }
        }));
        
        deltas.forEach((value, key) => {
            delta += value;
        });
    }

    const marketAddress = await pool.methods.marketMaker().call();
    // console.log('market', marketAddress);
    const market = getContract('MarketMaker.json', marketAddress, account);
    await swap(market, funding, delta, spotPrice, account);
    // print("{} options created at {} on exchange {} | pool {}: {}".format(token, datetime.now().strftime("%d/%m/%Y, %H:%M:%S"), exchange.address, pool, web3.toHex(web3.keccak(signed_txn.rawTransaction))))
    // const txPut = await exchange.methods.tradeOption(pool, optionTenor, putStrike, web3.utils.toWei(optionAmount.toString(),'ether'), 1, 0).send(); 
    
}

const main = async () => {
    try {
        const [account] = await web3.eth.getAccounts();
        const moret = getContract('Moret.json', moretAddress, account);
        const brokerAddress = await moret.methods.broker().call();
        const broker = getContract('MoretBroker.json', brokerAddress, account);

        const exchange = getContract('Exchange.json', exchangeAddress, account);
        const vaultAddress = await exchange.methods.vault().call();
        const vault = getContract('OptionVault.json', vaultAddress, account);
        
        const fundingAddress = await broker.methods.funding().call();
        const funding = getContract('ERC20.json', fundingAddress, account);

        // run hedges
        await Promise.all(tokens.map(async (token) => {
            const volchainAddress = await moret.methods.getVolatilityChain(tokenAddresses[token]).call();
            const oracle = getContract('VolatilityChain.json', volchainAddress, account);
            const pool = getContract('Pool.json', poolAddresses[token], account);
            await hedge(vault, oracle, funding, pool, account, false);
        }));
    } catch (error) {
        console.error(error)
    }
}

main();
