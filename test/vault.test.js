const { assert } = require("chai");

const FixedIncomeAnnuity = artifacts.require('./FixedIncomeAnnuity');

const oneday = 86400;
const fiaParams = [1.05e6, oneday * 7, 1e6, oneday, 0.95e6, oneday / 12, 0.9e6, 1e6];
const fipAddress = '0x2285ac4A9f53aD5aC0e36CC727a5a5E5641f6296'
const poolAddress = '0xE896ad64c88042F4f397DE14f3B034957969616C'
let token_name = process.env.TOKEN_NAME;

contract("Vault test", async accounts => {
    it("Add new Vault", async () => {
        const account_one = accounts[0];

        const fipName = 'Moret Variable Income ' + token_name;
        const fipSymbol = token_name + 'mvip'; 

        // const exchangeInstance = await Exchange.deployed();
        // const vaultInstance = await OptionVault.deployed();
        // const moretInstance = await Moret.deployed();

        const fipInstance = await FixedIncomeAnnuity.new(poolAddress, fipName, fipSymbol, fiaParams);
        // console.log(fipInstance.address);
        const fundingAddress = await fipInstance.funding();
        const funding = await ERC20.at(fundingAddress);
        
        // const fundingDecimals = await funding.decimals();
        const unitAsset = await fipInstance.getRollsUnitAsset();
        const unitsToInvest = 2
        const initialInvest = Number(unitAsset) * unitsToInvest;
        await funding.approve(fipInstance.address, process.env.MAX_AMOUNT, {from: account_one});
        await fipInstance.invest(web3.utils.toBN(initialInvest), { from: account_one });
        // await fipInstance.divest(web3.utils.toWei(unitsToInvest.toString()), { from: account_one });

        let initialTokens = await fipInstance.balanceOf(account_one);
        console.log(web3.utils.fromWei(initialTokens));
    })

    it("Vault rolls", async () => {
        const account_one = accounts[0];

        const fipInstance = await FixedIncomeAnnuity.at(fipAddress);
        await fipInstance.setParameters(fiaParams);
        
        // let unitAssets = await fipInstance.getRollsUnitAsset();
        // let params = await fipInstance.fiaParams();

        // const funding = await ERC20.at(web3.utils.toChecksumAddress(process.env.STABLE_COIN_ADDRESS));
        // let currentAssets = await funding.balanceOf(fipInstance.address);

        // let oracleAddress = await fipInstance.oracle();
        // let oracle = await VolatilityChain.at(oracleAddress);
        // let spotPrice = await oracle.queryPrice();
        // let optionAmount = Number(currentAssets) / 1e6 / parseFloat(web3.utils.fromWei(spotPrice))

        // let callStrike = parseFloat(web3.utils.fromWei(spotPrice)) * Number(params[0]) / 1e6
        
        // let optionPrice = await exchange.queryOption(web3.utils.toChecksumAddress(process.env.POOL), params[1], web3.utils.toWei(callStrike.toFixed(18)), web3.utils.toWei(optionAmount.toFixed(18)) , 0, 1, 0);

        await fipInstance.rollover({ from: account_one });

        // check options
        // let exchange = await Exchange.at(web3.utils.toChecksumAddress(process.env.EXCHANGE));
        // const exchangeInstance = await Exchange.deployed();
        // let vaultAddress = await exchangeInstance.vault();
        let vaultInstance = await OptionVault.deployed();
        let poolAddress = await fipInstance.pool();
        let optionList = await vaultInstance.getHolderOptions(poolAddress, fipInstance.address);
        
        let option = await vaultInstance.getOption(optionList[0])
        console.log(web3.utils.fromWei(optionCount));
    })
})

