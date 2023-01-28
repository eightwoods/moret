const {moretAddress, exchangeAddress, tokenAddresses, tokens} = require('./config.json');

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

const getVault = async (exchange, account) => {
    const vaultAddress = await exchange.methods.vault().call();
    return getContract('OptionVault.json', vaultAddress, account);
}

const expireOptions = async(broker, vault, exchange, token, account) => {
    // console.log(item, index);
    const pools = await broker.methods.getAllPools(tokenAddresses[token]).call();
    for (var i = 0; i < pools.length; i++) {
        const pool = pools[i];
        
        const any_expiring = await vault.methods.anyOptionExpiring(pool).call();
        console.log(token, pool, any_expiring);
        if (any_expiring){
            const expire_id = await vault.methods.getExpiringOptionId(pool).call();
            const tx = await exchange.methods.expireOption(expire_id, account).send();
            console.log(expire_id, tx);
        }
        // print("{} options created at {} on exchange {} | pool {}: {}".format(token, Date.now(), exchange.address, pool, web3.toHex(web3.keccak(signed_txn.rawTransaction))))
        // const txPut = await exchange.functions.tradeOption(pool, tenor, callStrike, web3.utils.toWei(amount,'ether'), 1, 0).send(); 
    };
}

const main = async () => {
    try {
        const account = await getAccount();
        const moret = getContract('Moret.json', moretAddress, account);
        const exchange = getContract('Exchange.json', exchangeAddress, account);
        const broker = await getBroker(moret, account);
        const vault = await getVault(exchange, account);
        
        await Promise.all(tokens.map(async (token) => {
            await expireOptions(broker, vault, exchange, token, account);
            // const contents = await fs.readFile(file, 'utf8')
            
          }));
    } catch (error) {
      console.error(error)
    }
}

main();
