const { moretAddress, exchangeAddress, tokenAddresses, tokens, chainId, maxAmount, hedgeThreshold, oneinchUrl, oneinchSlippage, defaultGas } = require('./config.json');
const optionAmount = 1;

const { DefenderRelayProvider } = require('defender-relay-client/lib/web3');
const Web3 = require('web3');

const credentials = { apiKey: process.env.RELAYER_KEY, apiSecret: process.env.RELAYER_SECRET };
const provider = new DefenderRelayProvider(credentials, { speed: 'fast' });
const web3 = new Web3(provider);

function getContract(abiFile, address, account) {
    var { abi } = require('../build/contracts/' + abiFile);
    var contract = new web3.eth.Contract(abi, address, { from: account });
    return contract;
}

const getAccount = async () => {
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

// Convert a hex string to a byte array
function hexToBytes(hex) {
    for (var bytes = [], c = 0; c < hex.length; c += 2)
        bytes.push(parseInt(hex.substr(c, 2), 16));
    return bytes;
}

// Convert a byte array to a hex string
function bytesToHex(bytes) {
    for (var hex = [], i = 0; i < bytes.length; i++) {
        var current = bytes[i] < 0 ? bytes[i] + 256 : bytes[i];
        hex.push((current >>> 4).toString(16));
        hex.push((current & 0xF).toString(16));
    }
    return hex.join("");
}

const swap = async(market, funding, delta, spot, account) => {
    const underlyingAddress = await market.methods.underlying().call();
    const underlying = getContract('ERC20.json', underlyingAddress, account);
    const underlyingDecimals = await underlying.methods.decimals().call();
    const fundingDecimals = await funding.methods.decimals().call();

    let currentHedge = await underlying.methods.balanceOf(market._address).call();
    currentHedge = parseFloat(web3.utils.fromWei(web3.utils.toBN(currentHedge).mul(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(underlyingDecimals))))))

    const tradeHedge = delta - currentHedge;
    const tradeValue = tradeHedge * spot;

    if (Math.abs(tradeValue) > hedgeThreshold){
        let spenderData = await fetchAsync(oneinchUrl[chainId] + "approve/spender");
        let spenderAddress = web3.utils.toChecksumAddress(spenderData['address']);
        console.log(tradeHedge, tradeValue, spot, spenderAddress);

        if (tradeHedge > 0) { 
            let tradeFunding = web3.utils.toBN(web3.utils.toWei(tradeValue.toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(fundingDecimals))));
            let swapParams = { 'fromTokenAddress': funding._address, 'toTokenAddress': underlyingAddress, 'amount': tradeFunding, 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' } ;
            swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
            // console.log(swapData);
            // await market.methods.trade(funding._address, tradeFunding, spenderAddress, hexToBytes(swapData['tx']['data']), defaultGas);
        }
        else{
            let tradeUnderlying = web3.utils.toBN(web3.utils.toWei(Math.abs(tradeHedge).toString(), 'ether')).div(web3.utils.toBN(10).pow(web3.utils.toBN(18 - Number(fundingDecimals))));
            let swapParams = { 'fromTokenAddress': underlyingAddress, 'toTokenAddress': funding._address, 'amount': tradeUnderlying, 'fromAddress': market._address, 'slippage': oneinchSlippage, 'disableEstimate': 'true' };
            swapData = await fetchAsyncWithParams(oneinchUrl[chainId] + 'swap', swapParams);
            console.log(swapData);
            // await market.methods.trade(underlyingAddress, tradeUnderlying, spenderAddress, hexToBytes(swapData['tx']['data']), defaultGas);
        }
    }
}

const hedge = async (vault, broker, oracle, funding, token, account) => {
    const pools = await broker.methods.getAllPools(tokenAddresses[chainId][token]).call();
    var ts = Math.round((new Date()).getTime() / 1000); // current UNIX timestamp in seconds
    var spot = await oracle.methods.queryPrice().call();
    spot = parseFloat(web3.utils.fromWei(spot));
    var vol = await oracle.methods.queryVol(86400).call();
    vol = parseFloat(web3.utils.fromWei(vol));
    var ann = await oracle.methods.getSqrtRatio(86400).call();
    console.log(spot, vol * parseFloat(web3.utils.fromWei(ann)));

    for (var i = 0; i < 1; i++) {
        const pool = getContract('Pool.json', pools[i], account);
        // const options = await vault.methods.getActiveOptions(pool).call();
        let delta = 0.001;
        // for (var j = 0;j < options.length(); j++){
        //     let option = await vault.methods.getOption(options[j]).call();
        //     let timeToExpiry = Math.max(0, option.maturity - ts); 
        //     let vol = await oracle.methods.queryVol(web3.utils.toBN(timeToExpiry.toString())).call();
        //     let optionDelta = await _option.calcDelta(_price, _vol, _includeExpiring);
        // }

        const marketAddress = await pool.methods.marketMaker().call();
        console.log('market', marketAddress);
        const market = getContract('MarketMaker.json', marketAddress, account);
        await swap(market, funding, delta, spot, account);
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
