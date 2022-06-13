const { moretAddress, exchangeAddress, tokenAddresses, aaveAddressesProvider, tokens, chainId, maxAmount, hedgeThreshold, oneinchUrl, oneinchSlippage, defaultGas, allowShorting, lendingPoolRateMode} = require('./config.json');
const optionAmount = 1;
const allowTrade = true;

const { DefenderRelayProvider } = require('defender-relay-client/lib/web3');
const Web3 = require('web3');
const lib = require('library');

const credentials = { apiKey: process.env.RELAYER_KEY, apiSecret: process.env.RELAYER_SECRET };
const provider = new DefenderRelayProvider(credentials, { speed: 'fast' });
const web3 = new Web3(provider);

function getContract(abiFile, address, account) {
    var { abi } = require('../build/contracts/' + abiFile);
    var contract = new web3.eth.Contract(abi, address, { from: account });
    return contract;
  }

const getAccount = async() =>{
    const [from] = await web3.eth.getAccounts();
    return from;
}

const getBroker = async (moret, account) => {
    const brokerAddress = await moret.methods.broker().call();
    return getContract('MoretBroker.json', brokerAddress, account);
}

const getFunding = async (broker, account) => {
    const fundingAddress = await broker.methods.funding().call();
    return getContract('ERC20.json', fundingAddress, account);
}

const getOracle = async (moret, tokenAddress, account) => {
    const volchainAddress = await moret.methods.getVolatilityChain(tokenAddress).call();
    return getContract('VolatilityChain.json', volchainAddress, account);
}

const getVault = async (exchange, account) => {
    const vaultAddress = await exchange.methods.vault().call();
    return getContract('OptionVault.json', vaultAddress, account);
}

async function fetchAsync(url) {
    let response = await fetch(url);
    let data = await response.json();
    return data;
}

async function fetchAsyncWithParams(requestURL, params) {
    var url = new URL(requestURL);
    Object.keys(params).forEach(key => url.searchParams.append(key, params[key]))
    let response = await fetch(url);
    let data = await response.json();
    return data;
}

async function getLendingPool(account) {
    let lendingPoolAddressesProvider = getContract('ILendingPoolAddressesProvider.json', aaveAddressesProvider[chainId], account);
    let lendingPoolAddress = await lendingPoolAddressesProvider.methods.getLendingPool().call();
    let lendingPool = getContract('ILendingPool.json', lendingPoolAddress, account);
    return lendingPool;
}

async function calcLoanTrade(targetHedge, underlyingAddress, spot, account){
    let lendingPoolAddressesProvider = getContract('ILendingPoolAddressesProvider.json', aaveAddressesProvider[chainId], account);
    let protocolProviderAddress = await lendingPoolAddressesProvider.methods.getAddress("0x1").call();
    let protocolProvider = getContract('IProtocolDataProvider.json', protocolProviderAddress, account);
    // let aaveLendingAddresses = await protocolProvider.methods.getReserveTokensAddresses(underlyingAddress).call(); // aTokenAddress, stableDebtTokenAddress, variableDebtTokenAddress
    // let stableDebtBalance = await loanBalance(aaveAddressesProvider[1], account);
    // let variableDebtBalance = await loanBalance(aaveAddressesProvider[2], account);
    // let debtBalance = stableDebtBalance + variableDebtBalance;

    let reserveConfig = await protocolProvider.methods.getReserveConfigurationData(underlyingAddress).call();
    let accountData = await protocolProvider.methods.getUserReserveData(underlyingAddress, account).call();
    let loanBalance = parseFloat(web3.utils.fromWei(accountData[1])) + parseFloat(web3.utils.fromWei(accountData[2]));
    let collateralBalance = parseFloat(web3.utils.fromWei(accountData[0]));

    let debtTrade = Math.max(0, -targetHedge) - loanBalance;
    let collateralChange = targetHedge * (reserveConfig[1] / 1e4) * spot - collateralBalance; 
    return [debtTrade, collateralChange];
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

const buyUnderlying = async (tradeValue, fundingDecimals, fundingAddress, underlyingAddress, marketAddress, spenderAddress) => {
    let tradeFunding = web3.utils.toBN(web3.utils.toWei(tradeValue.toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(fundingDecimals))));
    let swapParams = { 'fromTokenAddress': fundingAddress, 'toTokenAddress': underlyingAddress, 'amount': tradeFunding, 'fromAddress': marketAddress, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
    swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
    let callData = web3.utils.hexToBytes(swapData['tx']['data']);

    if (allowTrade) {
        await market.methods.trade(funding._address, tradeFunding, spenderAddress, callData, defaultGas).send();
    }
    else {
        console.log(funding._address, Number(tradeFunding), spenderAddress, callData, defaultGas);
    }
}

const sellUnderlying = async (tradeValue, fundingDecimals, fundingAddress, underlyingAddress, marketAddress, spenderAddress) => {
    let tradeFunding = web3.utils.toBN(web3.utils.toWei(tradeValue.toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(fundingDecimals))));
    let swapParams = { 'fromTokenAddress': fundingAddress, 'toTokenAddress': underlyingAddress, 'amount': tradeFunding, 'fromAddress': marketAddress, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
    swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
    let callData = web3.utils.hexToBytes(swapData['tx']['data']);

    if (allowTrade) {
        await market.methods.trade(funding._address, tradeFunding, spenderAddress, callData, defaultGas).send();
    }
    else {
        console.log(funding._address, Number(tradeFunding), spenderAddress, callData, defaultGas);
    }
}



const checkApproval = async(token, account, spender, spendAmount)=>{
    const approvedAmount = await token.methods.allowance(account, spender).call();
    if (web3.utils.toBN(web3.utils.toWei(spendAmount.toString(), 'ether')).gt(web3.utils.toBN(approvedAmount))) {
        await token.methods.approve(spendAmount, maxAmount).send();
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

    let spenderData = await fetchAsync(oneinchUrl[chainId] + "approve/spender");
    let spenderAddress = web3.utils.toChecksumAddress(spenderData['address']);
    console.log('spender address', spenderAddress);

    let currentHedge = await underlying.methods.balanceOf(market._address).call();
    currentHedge = parseFloat(web3.utils.fromWei(web3.utils.toBN(currentHedge).mul(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(underlyingDecimals))))));
    const tradeHedge = delta - currentHedge;
    var tradeValue = tradeHedge * spot;
    console.log(delta, currentHedge, tradeHedge, tradeValue, hedgeThreshold, borrowTrade, spot);

    if (Math.abs(tradeValue) > hedgeThreshold) {
        // Option 1: purchase hedges
        if (tradeHedge > 0) {
            let tradeFunding = web3.utils.toBN(web3.utils.toWei(tradeValue.toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(fundingDecimals))));
            let swapParams = { 'fromTokenAddress': funding._address, 'toTokenAddress': underlyingAddress, 'amount': tradeFunding, 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
            swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
            let callData = web3.utils.hexToBytes(swapData['tx']['data']);

            if (allowTrade) {
                await market.methods.trade(funding._address, tradeFunding, spenderAddress, callData, defaultGas).send();
            }
            else {
                console.log(funding._address, Number(tradeFunding), spenderAddress, callData, defaultGas);
            }
        }

        // Option 2: sell hedges
        if (tradeHedge < 0) {
            let tradeUnderlying = web3.utils.toBN(web3.utils.toWei(Math.abs(tradeHedge).toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(underlyingDecimals))));
            let swapParams = { 'fromTokenAddress': underlyingAddress, 'toTokenAddress': funding._address, 'amount': tradeUnderlying, 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
            swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
            // console.log(swapData);
            let callData = web3.utils.hexToBytes(swapData['tx']['data']);
            if (allowTrade) {
                await market.methods.trade(underlyingAddress, tradeUnderlying, spenderAddress, callData, defaultGas).send();
            }
            else {
                console.log(funding._address, Number(tradeFunding), spenderAddress, callData, defaultGas);
            }
        }
    }
}

// swap function adjust hedges of a given market maker contract address
// based on target hedge and current hedge positions, it calculates the following
// 1. buy underlying token
// 2. repayment of borrowing
// 3. additional borrowing from Aave
// 4. sell underlying token
const swapAndLoan = async(market, funding, delta, spot, account) => {
    const underlyingAddress = await market.methods.underlying().call();
    const underlying = getContract('ERC20.json', underlyingAddress, account);
    const underlyingDecimals = await underlying.methods.decimals().call();
    const fundingDecimals = await funding.methods.decimals().call();

    let spenderData = await fetchAsync(oneinchUrl[chainId] + "approve/spender");
    let spenderAddress = web3.utils.toChecksumAddress(spenderData['address']);
    console.log('spender address', spenderAddress);

    let currentHedge = await underlying.methods.balanceOf(market._address).call();
    currentHedge = parseFloat(web3.utils.fromWei(web3.utils.toBN(currentHedge).mul(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(underlyingDecimals))))));
    let lendingPool = await getLendingPool(account);
    const loanTrade = await calcLoanTrade(delta, underlyingAddress, account);
    const loanTradeValue = loanTrade[0] * spot; 

    // // if loans needs to be repaid
    // if (loanTradeValue < -hedgeThreshold){
    //     // trade for tokens needed for loan repayment.
    //     await buyUnderlying(Math.abs(loanTradeValue), fundingDecimals, funding._address, underlyingAddress, market._address, spenderAddress).send();

    //     // repay loans
    //     await checkApproval(underlying, account, spenderAddress, Math.abs(loanTrade[0]));
    //     await lendingPool.methods.repay(underlyingAddress, web3.utils.toWei(Math.abs(loanTrade[0]),'ether'), lendingPoolRateMode, market._address);

    //     // reduce collaterals if needed

    // }
    // else if (loanTradeValue > hedgeThreshold){
    //     // more collaterals if needed



    // }

    const tradeHedge = delta - currentHedge ;
    var tradeValue = tradeHedge * spot;
    console.log(delta, currentHedge, tradeHedge, tradeValue, hedgeThreshold, borrowTrade, spot);



    if (Math.abs(tradeValue) > hedgeThreshold){
        

        // Step 1: purchase hedges
        if (tradeHedge > 0) { 
            let tradeFunding = web3.utils.toBN(web3.utils.toWei(tradeValue.toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(fundingDecimals))));
            let swapParams = { 'fromTokenAddress': funding._address, 'toTokenAddress': underlyingAddress, 'amount': tradeFunding, 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' } ;
            swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
            let callData = web3.utils.hexToBytes(swapData['tx']['data']);

            if (allowTrade){
                await market.methods.trade(funding._address, tradeFunding, spenderAddress, callData, defaultGas).send();
            }
            else{
                console.log(funding._address, Number(tradeFunding), spenderAddress, callData, defaultGas);
            }
        }

        // // Step 2: repay borrowing
        // if (tradeHedge > 0){
        //     let repayAmount = Math.min(tradeHedge, Math.abs(currentHedge));
        //     let repayValue = repayAmount * spot;
        //     console.log("Repayment loan", repayAmount, repayValue);

            
        // }

        // // Step 3: new borrowing
        // if (allowShorting){

        // }

        // Step 4: sell hedges
        if (tradeHedge<0) {
            let tradeUnderlying = web3.utils.toBN(web3.utils.toWei(Math.abs(tradeHedge).toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(underlyingDecimals))));
            let swapParams = { 'fromTokenAddress': underlyingAddress, 'toTokenAddress': funding._address, 'amount': tradeUnderlying, 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
            swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
            // console.log(swapData);
            let callData = web3.utils.hexToBytes(swapData['tx']['data']);
            if (allowTrade) {
                await market.methods.trade(underlyingAddress, tradeUnderlying, spenderAddress, callData, defaultGas).send();
            }
            else{
                console.log(funding._address, Number(tradeFunding), spenderAddress, callData, defaultGas);
            }
        }
    }
}

const hedge = async (vault, broker, oracle, funding, token, account) => {
    const pools = await broker.methods.getAllPools(tokenAddresses[chainId][token]).call();
    var ts = Math.round((new Date()).getTime() / 1000); // current UNIX timestamp in seconds
    var spot = await oracle.methods.queryPrice().call();
    var vol = await oracle.methods.queryVol(86400).call();
    var ann = await oracle.methods.getSqrtRatio(86400).call();
    console.log(web3.utils.fromWei(spot), parseFloat(web3.utils.fromWei(vol)) * parseFloat(web3.utils.fromWei(ann)));

    for (var i = 0; i < 1; i++) {
        const pool = getContract('Pool.json', pools[i], account);
        // const options = await vault.methods.getActiveOptions(pool).call();
        // let delta = 0.00005;
        let delta = await vault.methods.calculateAggregateDelta(pools[i], spot, false).call();
        delta = parseFloat(web3.utils.fromWei(delta));
        // for (var j = 0;j < options.length(); j++){
        //     let option = await vault.methods.getOption(options[j]).call();
        //     let timeToExpiry = Math.max(0, option.maturity - ts); 
        //     let vol = await oracle.methods.queryVol(web3.utils.toBN(timeToExpiry.toString())).call();
        //     let optionDelta = await _option.calcDelta(_price, _vol, _includeExpiring);
        // }

        const marketAddress = await pool.methods.marketMaker().call();
        console.log('market', marketAddress);
        const market = getContract('MarketMaker.json', marketAddress, account);
        await swap(market, funding, delta, parseFloat(web3.utils.fromWei(spot)), account);
        // print("{} options created at {} on exchange {} | pool {}: {}".format(token, datetime.now().strftime("%d/%m/%Y, %H:%M:%S"), exchange.address, pool, web3.toHex(web3.keccak(signed_txn.rawTransaction))))
        // const txPut = await exchange.methods.tradeOption(pool, optionTenor, putStrike, web3.utils.toWei(optionAmount.toString(),'ether'), 1, 0).send(); 
    };
}

const main = async () => {
    try {
        const account = await getAccount();
        const moret = getContract('Moret.json', moretAddress[chainId], account);
        const exchange = getContract('Exchange.json', exchangeAddress[chainId], account);
        const broker = await getBroker(moret, account);
        const vault = await getVault(exchange, account);

        // check max allowance
        const funding = await getFunding(broker, account);
        const approvedAmount = await funding.methods.allowance(account, exchangeAddress[chainId]).call();
        if (web3.utils.toBN(web3.utils.toWei(optionAmount.toString(), 'ether')).gt(web3.utils.toBN(approvedAmount))) {
            await funding.methods.approve(exchangeAddress[chainId], maxAmount).send();
        }

        await Promise.all(tokens.map(async (token) => {
            const oracle = await getOracle(moret, tokenAddresses[chainId][token], account);
            await hedge(vault, broker, oracle, funding, token, account);
        }));
    } catch (error) {
        console.error(error)
    }
}

main();
