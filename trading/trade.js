const optionTenor = 86400;
const optionAmount = 0.01;

const {moretAddress, exchangeAddress, tokenAddresses, tokens, chainId, minTicks, maxAmount} = require('./config.json');

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

const getChain = async (moret, tokenAddress, account) => {
  const volchainAddress = await moret.methods.getVolatilityChain(tokenAddress).call();
  return getContract('VolatilityChain.json', volchainAddress, account);
}

const tradeOptions = async(broker, chain, exchange, token) => {
    // console.log(item, index);
    const spotPrice = await chain.methods.queryPrice().call();
    const callStrike = web3.utils.toWei((Math.ceil(parseFloat(web3.utils.fromWei(spotPrice,'ether'))/minTicks[token]) * minTicks[token]).toString(),'ether');
    const putStrike = web3.utils.toWei((Math.floor(parseFloat(web3.utils.fromWei(spotPrice,'ether'))/minTicks[token]) * minTicks[token]).toString(),'ether');
  
    const pools = await broker.methods.getAllPools(tokenAddresses[chainId][token]).call();
    for (var i = 0; i < 1; i++) {
        const pool = pools[i];
        const cost = await exchange.methods.queryOption(pool, optionTenor, callStrike, web3.utils.toWei(optionAmount.toString(),'ether'), 0 , 0, false).call();
        console.log(web3.utils.fromWei(spotPrice,'ether'), web3.utils.fromWei(callStrike, 'ether'), web3.utils.fromWei(putStrike, 'ether'), web3.utils.fromWei(cost[0], 'ether'));
        const tx = await exchange.methods.tradeOption(pool, optionTenor, callStrike, web3.utils.toWei(optionAmount.toString(),'ether'), 0 , 0).send();
        // print("{} options created at {} on exchange {} | pool {}: {}".format(token, datetime.now().strftime("%d/%m/%Y, %H:%M:%S"), exchange.address, pool, web3.toHex(web3.keccak(signed_txn.rawTransaction))))
        const txPut = await exchange.functions.tradeOption(pool, optionTenor, putStrike, web3.utils.toWei(optionAmount.toString(),'ether'), 1, 0).send(); 
    };
}

const main = async () => {
    try {
        const account = await getAccount();
        const moret = getContract('Moret.json', moretAddress, account);
        const exchange = getContract('Exchange.json', exchangeAddress, account);
        const broker = await getBroker(moret, account);

        // check max allowance
        const funding = await getFunding(broker, account);
        const approvedAmount = await funding.methods.allowance(account, exchangeAddress).call();
        if(web3.utils.toBN(web3.utils.toWei(optionAmount.toString(),'ether')).gt(web3.utils.toBN(approvedAmount))){
          await funding.methods.approve(exchangeAddress, maxAmount).send();
        }
        
        await Promise.all(tokens.map(async (token) => {
          const chain = await getChain(moret, tokenAddresses[chainId][token], account);
          await tradeOptions(broker, chain, exchange, token);
          }));
    } catch (error) {
      console.error(error)
    }
}

main();
