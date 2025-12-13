import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();
import FactoryArtifact  from '@uniswap/v2-core/build/UniswapV2Factory.json'
import RouterArtifact  from '@uniswap/v2-periphery/build/UniswapV2Router02.json'
import WETHArtifact from '@uniswap/v2-periphery/build/WETH9.json'

const { abi: FactoryABI, bytecode: FactoryBytecode } = FactoryArtifact
const { abi: RouterABI, bytecode: RouterBytecode } = RouterArtifact
const { abi: WETHABI, bytecode: WETHBytecode } = WETHArtifact

describe('MemeToken (LMEME) Token', function () {
    let MemeToken: any
    let memetoken: any
    let owner: any
    let user1: any
    let user2: any
    let marketingWallet: any
    let weth: any
    let router: any
    let routerAddress: string
    let factory: any
    let pairAddress: string
    let memetokenAddress: string
    let wethInPair: bigint
    let memeInPair: bigint

    beforeEach(async function () {
        [owner, user1, user2, marketingWallet] = await ethers.getSigners()
        console.log('Deploying contracts with the account:', owner.address)

        // 1. 部署 WETH 模拟合约（Uniswap 需要）
        const WETHFactory = new ethers.ContractFactory(WETHABI, WETHBytecode, owner)
        weth = await WETHFactory.deploy()
        await weth.waitForDeployment()
        console.log('WETH deployed to:', await weth.getAddress())

        // 2. 部署 Uniswap V2 Factory
        const Factory = new ethers.ContractFactory(FactoryABI, FactoryBytecode, owner)
        factory = await Factory.deploy(owner.address) // feeTo = owner
        await factory.waitForDeployment()
        console.log('UniswapV2Factory deployed to:', await factory.getAddress())

        // 3. 部署 Uniswap V2 Router
        const Router = new ethers.ContractFactory(RouterABI, RouterBytecode, owner)
        router = await Router.deploy(await factory.getAddress(), await weth.getAddress())
        await router.waitForDeployment()
        routerAddress = await router.getAddress()
        console.log('UniswapV2Router02 deployed to:', routerAddress)

        // 4. 部署代币合约
        MemeToken = await ethers.getContractFactory('MemeToken')
        memetoken = await MemeToken.deploy(routerAddress, marketingWallet.address)
        await memetoken.waitForDeployment()
        memetokenAddress = await memetoken.getAddress()
        console.log('MemeToken deployed to:', memetokenAddress)

        //验证路由、交易对设置情况
        const routerAddressCheck = await memetoken.uniswapV2Router()
        expect(routerAddressCheck).to.equal(routerAddress)
        pairAddress = await memetoken.uniswapV2Pair()
        expect(pairAddress).to.not.equal(ethers.ZeroAddress)

        // 验证免手续费名单
        expect(await memetoken.isExcludedFromTax(routerAddress)).to.be.true
        expect(await memetoken.isExcludedFromTax(pairAddress)).to.be.true
        expect(await memetoken.isExcludedFromTax(memetokenAddress)).to.be.true
        const ownerAddress = await owner.getAddress()
        expect(await memetoken.isExcludedFromTax(ownerAddress)).to.be.true
        expect(await memetoken.isExcludedFromTax(ethers.ZeroAddress)).to.be.true

        console.log('beforeEach is ok! ')
    })

    //辅助函数，获取指定交易对中 LMEME 和 WETH 的流动性余额
    async function getPairLiquidity() {
        const IUniswapV2Pair = [
            'function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)',
            'function token0() external view returns (address)',
            'function token1() external view returns (address)'
        ]

        const provider = ethers.provider
        const pair = new ethers.Contract(pairAddress, IUniswapV2Pair, provider)

        // 获取 reserves
        const reserves = await pair.getReserves()
        const reserve0 = reserves[0]
        const reserve1 = reserves[1]

        // 获取 token0 和 token1
        const token0 = await pair.token0()
        const token1 = await pair.token1()

        //判断哪个是 MemeToken，哪个是 WETH
        //let memeInPair, wethInPair;
        if (token0.toLowerCase() === memetokenAddress.toLowerCase()) {
            memeInPair = reserve0
            wethInPair = reserve1
        } else if (token1.toLowerCase() === memetokenAddress.toLowerCase()) {
            memeInPair = reserve1
            wethInPair = reserve0
        } else {
            throw new Error('Pair does not contain MemeToken')
        }

        // 返回格式化后的结果（人类可读）
        //memeBalanceBN = ethers.formatUnits(memeInPair, 18); // string: "100.0"
        //wethBalanceBN = ethers.formatEther(wethInPair);     // string: "1.0"
    }

    //辅助函数，添加初始流动性
    async function addLiquidity() {
        const tokenAmount = ethers.parseUnits('500', 18) // 500枚代币
        const ethAmount = ethers.parseEther('1') // 1 ETH

        //Owner 发送 ETH 给合约
        await owner.sendTransaction({ to: memetokenAddress, value: ethAmount })
        expect(await ethers.provider.getBalance(memetokenAddress)).to.equal(ethAmount)

        //Owner 授权 Router 使用代币
        await memetoken.approve(routerAddress, tokenAmount)

        //调用合约的 addInitialLiquidity 方法
        const tx = await memetoken.addInitialLiquidity(tokenAmount, ethAmount)
        await tx.wait() // 等待交易上链！
        console.log('Liquidity added via addInitialLiquidity')

        //获取交易后的 pair 余额
        await getPairLiquidity()

        //输出结果
        console.log('Final Liquidity in Pair:')
        //console.log("MEME in Pair:", ethers.formatUnits(memeInPair, 18), "LMEME");
        //console.log("ETH (as WETH) in Pair:", ethers.formatEther(ethInPair), "WETH");

        console.log('ETH (as WETH) in Pair:', ethers.formatEther(wethInPair), 'WETH')
        console.log('MEME in Pair:', ethers.formatUnits(memeInPair, 18), 'LMEME')

        //验证
        expect(wethInPair).to.equal(ethAmount, 'ETH amount in pair does not match')
        expect(memeInPair).to.equal(tokenAmount, 'MEME amount in pair does not match')
    }

    // 辅助函数：暂停指定毫秒数
    function delay(ms: number): Promise<void> {
        return new Promise((resolve) => setTimeout(resolve, ms))
    }

    it('Should add initial liquidity successfully', async function () {
        const tokenAmount = ethers.parseUnits('500', 18) // 500枚代币
        const ethAmount = ethers.parseEther('1') // 1 ETH

        // 获取交易前的 pair 余额
        const pairBalanceBefore = await memetoken.balanceOf(pairAddress)
        expect(pairBalanceBefore).to.equal(0, 'Pair should have no tokens before liquidity added')

        //Owner 发送 代币、 ETH 给合约
        //await memetoken.transfer(memetokenAddress, tokenAmount);
        //expect(await memetoken.balanceOf(memetokenAddress)).to.equal(tokenAmount);
        await owner.sendTransaction({ to: memetokenAddress, value: ethAmount })
        expect(await ethers.provider.getBalance(memetokenAddress)).to.equal(ethAmount)

        //Owner 授权 Router 使用代币
        await memetoken.approve(routerAddress, tokenAmount)

        //调用合约的 addInitialLiquidity 方法
        await expect(memetoken.addInitialLiquidity(tokenAmount, ethAmount)).to.not.be.reverted

        // 验证交易对余额
        const pairBalance = await memetoken.balanceOf(pairAddress) //代币
        expect(pairBalance).to.equal(tokenAmount)

        const wethInPair = await weth.balanceOf(pairAddress)
        expect(wethInPair).to.equal(ethAmount)

        // 验证合约余额清零
        expect(await memetoken.balanceOf(memetokenAddress)).to.equal(0)
        expect(await ethers.provider.getBalance(memetokenAddress)).to.equal(0)

        console.log('Contract successfully added liquidity using its own funds')
    })

    it('should collect 5% buy tax and send to contract when user buys from pair', async function () {
        const buyEthAmount = ethers.parseEther('0.1') // 用户用 0.1 ETH 买入
        const path = [await router.WETH(), memetokenAddress]
        const deadline = Math.floor(Date.now() / 1000) + 60 * 20 // 20分钟

        // 使用辅助函数添加流动性
        await addLiquidity()

        //用户交易前，代币合约余额，用户代币余额，营销钱包余额
        const contractBalanceBefore = await memetoken.balanceOf(memetokenAddress)
        console.log('contractBalanceBefore:', contractBalanceBefore)
        const userBalanceBefore = await memetoken.balanceOf(user1.address)
        console.log('userBalanceBefore:', userBalanceBefore)
        const marketingWalletBalanceBefore = await memetoken.balanceOf(marketingWallet.address)
        console.log('marketingWalletBalanceBefore:', marketingWalletBalanceBefore)

        // 用户（user1）通过 Router 买入代币
        const tx = await router.connect(user1).swapExactETHForTokens(0, path, user1.address, deadline, { value: buyEthAmount })
        await tx.wait()
        console.log('第一次购买成功！')

        //等待 5 秒
        await delay(5000)

        //连续买两次
        const tx2 = await router.connect(user1).swapExactETHForTokens(0, path, user1.address, deadline, { value: buyEthAmount })
        await tx2.wait()
        console.log('第二次购买成功！')

        //用户交易后，代币合约余额，用户代币余额，营销钱包余额
        const contractBalanceAfter = await memetoken.balanceOf(await memetoken.getAddress())
        console.log('contractBalanceAfter:', contractBalanceAfter)
        const userBalanceAfter = await memetoken.balanceOf(user1.address)
        console.log('userBalanceAfter:', userBalanceAfter)
        const marketingWalletBalanceAfter = await memetoken.balanceOf(marketingWallet.address)
        console.log('marketingWalletBalanceAfter:', marketingWalletBalanceAfter)

        //合约收到的税费
        const taxReceived = contractBalanceAfter - contractBalanceBefore
        console.log('taxReceived:', taxReceived)

        //用户1收到的代币数
        const userReceived = userBalanceAfter - userBalanceBefore
        console.log('userReceived:', userReceived)

        //验证合约收到的税费必须正好是 5%
        const taxReceivedFormatted = parseFloat(ethers.formatUnits(taxReceived, 18))
        const marketingReceivedFormatted = parseFloat(ethers.formatUnits(marketingWalletBalanceAfter, 18))
        const userReceivedFormatted = parseFloat(ethers.formatUnits(userReceived, 18))

        const totalTax = taxReceivedFormatted + marketingReceivedFormatted
        const totalDistributed = userReceivedFormatted + totalTax
        const realTaxRate = (totalTax / totalDistributed) * 100

        console.log('realTaxRate:', realTaxRate)
        //expect(realTaxRate).to.equal((5n), "买入税率必须正好是 5%");
        expect(realTaxRate).to.be.closeTo(5, 0.1, '买入税率应在 5% ±0.1% 范围内')

        //获取交易后的 pair 余额
        await getPairLiquidity()
        console.log('buy after ETH (as WETH) in Pair:', ethers.formatEther(wethInPair), 'WETH')
        console.log('buy after MEME in Pair:', ethers.formatUnits(memeInPair, 18), 'LMEME')
    })

    it('should collect 8% sell tax when user sells via router', async function () {
        const buyEthAmount = ethers.parseEther('0.2') // 用户用 0.2 ETH 买入
        let sellAmount = ethers.parseUnits('20', 18) // 用户卖出 10 个代币
        const pathBuy = [await router.WETH(), memetokenAddress]
        const pathSell = [memetokenAddress, await router.WETH()]
        const deadline = Math.floor(Date.now() / 1000) + 60 * 20 // 20分钟

        // 使用辅助函数添加流动性
        await addLiquidity()

        // 用户（user1）通过 Router 买入代币
        const txBuy = await router.connect(user1).swapExactETHForTokens(0, pathBuy, user1.address, deadline, { value: buyEthAmount })
        await txBuy.wait()
        console.log('购买成功！')

        //用户代币余额
        const userBalanceBefore = await memetoken.balanceOf(user1.address)
        console.log('userBalanceBefore:', ethers.formatUnits(userBalanceBefore, 18))

        //获取交易后的 pair 余额
        await getPairLiquidity()
        console.log('buy after ETH (as WETH) in Pair:', ethers.formatEther(wethInPair), 'WETH')
        console.log('buy after MEME in Pair:', ethers.formatUnits(memeInPair, 18), 'LMEME')

        //合约、营销钱包余额
        const contractBalanceBefore = await memetoken.balanceOf(memetokenAddress)
        console.log('contractBalanceBefore:', ethers.formatUnits(contractBalanceBefore, 18))
        const marketingWalletBalanceBefore = await memetoken.balanceOf(marketingWallet.address)
        console.log('marketingWalletBalanceBefore:', ethers.formatUnits(marketingWalletBalanceBefore, 18))

        // 获取用户 ETH 余额（卖出前）
        const userETHBalanceBefore = await ethers.provider.getBalance(user1.address)
        console.log('User ETH Balance Before Sell:', ethers.formatEther(userETHBalanceBefore), 'ETH')

        //设置不开启自动将税费转为流动性的功能
        await memetoken.updateSwapAndLiquifyEnabled(false)

        //预估卖出 10 LMEME 能换多少 ETH
        let amountsOut = await router.getAmountsOut(sellAmount, pathSell)
        let estimatedETH = amountsOut[1] // 第二个是输出的 ETH 数量
        console.log('Estimated ETH out:', ethers.formatEther(estimatedETH))

        //设置最小输出为预估值的 99%（防止滑点）
        let amountOutMin = (estimatedETH * 90n) / 100n
        console.log('amountOutMin:', ethers.formatEther(amountOutMin))

        // 用户（user1）授权 Router 使用其代币
        await memetoken.connect(user1).approve(routerAddress, sellAmount)
        // 用户（user1）通过 Router 卖出代币
        //转账时扣税：swapExactTokensForETHSupportingFeeOnTransferTokens
        //转账时不扣税：swapExactTokensForETH
        const txSell = await router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(sellAmount, amountOutMin, pathSell, user1.address, deadline)
        await txSell.wait()
        console.log('第一次卖出成功！')

        //=====================模拟第二次卖出 start =====================

        //等待 5 秒
        await delay(5000)

        amountsOut = await router.getAmountsOut(sellAmount, pathSell)
        estimatedETH = amountsOut[1]
        amountOutMin = (estimatedETH * 90n) / 100n
        // 用户（user1）授权 Router 使用其代币
        await memetoken.connect(user1).approve(routerAddress, sellAmount)
        const txSell2 = await router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(sellAmount, amountOutMin, pathSell, user1.address, deadline)
        await txSell2.wait()
        console.log('第二次卖出成功！')
        sellAmount += sellAmount

        //=====================模拟第二次卖出 end =====================

        //用户代币余额
        const userBalanceAfter = await memetoken.balanceOf(user1.address)
        console.log('userBalanceAfter:', ethers.formatUnits(userBalanceAfter, 18))
        //合约、营销钱包代币余额
        const contractBalanceAfter = await memetoken.balanceOf(memetokenAddress)
        console.log('contractBalanceAfter:', ethers.formatUnits(contractBalanceAfter, 18))
        const marketingWalletBalanceAfter = await memetoken.balanceOf(marketingWallet.address)
        console.log('marketingWalletBalanceAfter:', ethers.formatUnits(marketingWalletBalanceAfter, 18))

        //实际收到的税费
        const taxReceived = contractBalanceAfter - contractBalanceBefore + (marketingWalletBalanceAfter - marketingWalletBalanceBefore)
        console.log('taxReceived:', ethers.formatUnits(taxReceived, 18))

        //计算税率
        const sellAmountInEther = parseFloat(ethers.formatUnits(sellAmount, 18))
        const taxReceivedInEther = parseFloat(ethers.formatUnits(taxReceived, 18))
        const realTaxRate = (taxReceivedInEther / sellAmountInEther) * 100
        console.log('realTaxRate:', realTaxRate)
        expect(realTaxRate).to.be.closeTo(8, 0.1, '卖出税率应该在 8% ±0.1% 范围内')

        // 获取用户 ETH 余额（卖出后）
        const userETHBalanceAfter = await ethers.provider.getBalance(user1.address)
        console.log('User ETH Balance After Sell:', ethers.formatEther(userETHBalanceAfter), 'ETH')

        // 计算用户收到的 ETH 数量
        const ethReceived = userETHBalanceAfter - userETHBalanceBefore
        console.log('User get ETH after sell:', ethers.formatEther(ethReceived), 'ETH')

        //获取交易后的 pair 余额
        await getPairLiquidity()
        console.log('buy after ETH (as WETH) in Pair:', ethers.formatEther(wethInPair), 'WETH')
        console.log('buy after MEME in Pair:', ethers.formatUnits(memeInPair, 18), 'LMEME')
    })

    it('should swapAndLiquify after user sells via router', async function () {
        const buyEthAmount = ethers.parseEther('0.2') // 用户用 0.2 ETH 买入
        let sellAmount = ethers.parseUnits('20', 18) // 用户卖出 10 个代币
        const pathBuy = [await router.WETH(), memetokenAddress]
        const pathSell = [memetokenAddress, await router.WETH()]
        const deadline = Math.floor(Date.now() / 1000) + 60 * 20 // 20分钟

        // 使用辅助函数添加流动性
        await addLiquidity()

        // 用户（user1）通过 Router 买入代币
        const txBuy = await router.connect(user1).swapExactETHForTokens(0, pathBuy, user1.address, deadline, { value: buyEthAmount })
        await txBuy.wait()
        console.log('购买成功！')

        //用户代币余额
        const userBalanceBefore = await memetoken.balanceOf(user1.address)
        console.log('userBalanceBefore:', ethers.formatUnits(userBalanceBefore, 18))

        //获取交易后的 pair 余额
        await getPairLiquidity()
        console.log('buy after ETH (as WETH) in Pair:', ethers.formatEther(wethInPair), 'WETH')
        console.log('buy after MEME in Pair:', ethers.formatUnits(memeInPair, 18), 'LMEME')

        //合约、营销钱包余额
        const contractBalanceBefore = await memetoken.balanceOf(memetokenAddress)
        console.log('contractBalanceBefore:', ethers.formatUnits(contractBalanceBefore, 18))
        const marketingWalletBalanceBefore = await memetoken.balanceOf(marketingWallet.address)
        console.log('marketingWalletBalanceBefore:', ethers.formatUnits(marketingWalletBalanceBefore, 18))

        // 获取用户 ETH 余额（卖出前）
        const userETHBalanceBefore = await ethers.provider.getBalance(user1.address)
        console.log('User ETH Balance Before Sell:', ethers.formatEther(userETHBalanceBefore), 'ETH')

        //预估卖出 10 LMEME 能换多少 ETH
        let amountsOut = await router.getAmountsOut(sellAmount, pathSell)
        let estimatedETH = amountsOut[1] // 第二个是输出的 ETH 数量
        console.log('Estimated ETH out:', ethers.formatEther(estimatedETH))

        //设置最小输出为预估值的 99%（防止滑点）
        let amountOutMin = (estimatedETH * 90n) / 100n
        console.log('amountOutMin:', ethers.formatEther(amountOutMin))

        // 用户（user1）授权 Router 使用其代币
        await memetoken.connect(user1).approve(routerAddress, sellAmount)
        // 用户（user1）通过 Router 卖出代币
        //转账时扣税：swapExactTokensForETHSupportingFeeOnTransferTokens
        //转账时不扣税：swapExactTokensForETH
        const txSell = await router.connect(user1).swapExactTokensForETHSupportingFeeOnTransferTokens(sellAmount, amountOutMin, pathSell, user1.address, deadline)
        await txSell.wait()
        console.log('第一次卖出成功！')

        //用户代币余额
        const userBalanceAfter = await memetoken.balanceOf(user1.address)
        console.log('userBalanceAfter:', ethers.formatUnits(userBalanceAfter, 18))
        //合约、营销钱包代币余额
        const contractBalanceAfter = await memetoken.balanceOf(memetokenAddress)
        console.log('contractBalanceAfter:', ethers.formatUnits(contractBalanceAfter, 18))
        const marketingWalletBalanceAfter = await memetoken.balanceOf(marketingWallet.address)
        console.log('marketingWalletBalanceAfter:', ethers.formatUnits(marketingWalletBalanceAfter, 18))

        // 获取用户 ETH 余额（卖出后）
        const userETHBalanceAfter = await ethers.provider.getBalance(user1.address)
        console.log('User ETH Balance After Sell:', ethers.formatEther(userETHBalanceAfter), 'ETH')

        // 计算用户收到的 ETH 数量
        const ethReceived = userETHBalanceAfter - userETHBalanceBefore
        console.log('User get ETH after sell:', ethers.formatEther(ethReceived), 'ETH')

        //获取交易后的 pair 余额
        await getPairLiquidity()
        console.log('sell after ETH (as WETH) in Pair:', ethers.formatEther(wethInPair), 'WETH')
        console.log('sell after MEME in Pair:', ethers.formatUnits(memeInPair, 18), 'LMEME')
    })
})
