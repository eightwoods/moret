const { assert } = require("chai");

const FixedIndex = artifacts.require('./FixedIndex');
const Perp = artifacts.require('./Perp');

const poolAddress = '0x33B53299bC6C5D3433AeF84397A1B82e6F7c7E81'
const oneday = 86400;     

contract("Vault test", async accounts => {
    // deploy fixed index annuity
    it("Add new FI", async () => {
        const fiaParams = [1.05e6, oneday * 28, 1e6, oneday * 7, 0.95e6, oneday, 0.9e6, 1e6];
        
        const account_one = accounts[0];

        const fipInstance = await FixedIndex.new(poolAddress, 'Moret Fixed Index ' + process.env.TOKEN_NAME, process.env.TOKEN_NAME + 'fi', fiaParams);
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

    it("FI rolls", async () => {
        const account_one = accounts[0];

        var fipInstance = await FixedIndex.at(fipAddress);
        await fipInstance.setParameters(fiaParams);
        var params = await fipInstance.fiaParams();

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

    // deploy perps
    it("Add new Perp", async () => {
        // strike, strike2, leverage, critical level and 0.03% daily penalty fee which is ~10% annually
        var params = [0.75, 0.8, 3.5, 2.5, 0.0003] // for 3x perp
        // var params = [0.55, 0.6, 2, 1.75, 0.0003] // for 2x perp
        var tokenDescription = 'Moret Perpetual ' + process.env.TOKEN_NAME + ' ' + ((params[2] + params[3]) / 2).toFixed(0) + 'x'
        var tokenSymbol = process.env.TOKEN_NAME + ((params[2] + params[3]) / 2).toFixed(0) + 'x'
        var perpParams = [true, web3.utils.toWei(params[0].toString()), web3.utils.toWei(params[1].toString()), web3.utils.toWei(params[2].toString()), web3.utils.toWei(params[3].toString()), web3.utils.toWei(params[4].toString()), oneday*30]
        
        const account_one = accounts[0];

        var perpInstance = await Perp.new(poolAddress, tokenDescription, tokenSymbol, perpParams)
        console.log(perpInstance.address);

        let currentLev = await perpInstance.getCurrentLeverage();
        console.log(web3.utils.fromWei(currentLev))

        const fundingAddress = await perpInstance.funding();
        const fundingDecimals = await perpInstance.fundingDecimals();
        const funding = await ERC20.at(fundingAddress);

        const initialInvest = 0.1 * (10 ** fundingDecimals);
        await funding.approve(perpInstance.address, process.env.MAX_AMOUNT, { from: account_one });
        // await funding.transfer(perpInstance.address, web3.utils.toBN(initialInvest), {from:account_one});
        await perpInstance.invest(web3.utils.toBN(initialInvest), { from: account_one });
        await perpInstance.createOption({ from: account_one })
        await perpInstance.unwindOption({ from: account_one })
        await perpInstance.setLiquidation(true, { from: account_one })
        
        // await perpInstance.divest(web3.utils.toBN(initialInvest), { from: account_one });

        let initialTokens = await perpInstance.balanceOf(account_one);
        console.log(web3.utils.fromWei(initialTokens));
    })

})

