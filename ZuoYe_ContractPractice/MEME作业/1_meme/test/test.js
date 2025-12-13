const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers }  = require("hardhat");
const { expect } = require("chai");

describe("ShibMemeToken",async function () {

    async function deployTokenFixture() {
        const [owner, marketingWallet, devWallet, user1, user2, user3]=await ethers.getSigners();

        // unswap
        

        const UniswapV2Factory = await ethers.getContractFactory("UniswapV2FactoryMock");
        const factory = await UniswapV2Factory.deploy();

        const uniswapv2router = await ethers.getContractFactory("UniswapV2Router02Mock");
        const router = await uniswapv2router.deploy(await factory.getAddress());

        // token

        const shibMemeToken=await ethers.getContractFactory("shibMeme");
        const totalSupply = await ethers.parseEther("10000000000")
        const token=await shibMemeToken.deploy(
            "Shiba Meme",
            "SHIBM",
            totalSupply,
            await router.getAddress(),
            marketingWallet.address,
            devWallet.address

        );
        return { token, router, owner, marketingWallet, devWallet, user1, user2, user3, totalSupply };

    };

    describe("deployment",function () {
        it("tokenname",async function () {
            const { token } = await loadFixture(deployTokenFixture);

            expect(await token.name()).to.equal("Shiba Meme");
            expect(await token.symbol()).to.equal("SHIBM");    

        });

        it("铸造",async function () {
            const { token,owner,totalSupply } = await loadFixture(deployTokenFixture);
            const value = await token.balanceOf(owner.address);
            expect(value).to.equal(totalSupply);
            console.log(value)
            
            expect(await token.totalSupply()).to.equal(totalSupply);   

        });

        it("tax",async function () {
            const { token } = await loadFixture(deployTokenFixture);
            
            const [buytax,selltax] = await token.getTaxRates();
            
            console.log(buytax)
            console.log(selltax)


        });

        it("limit",async function () {
            const { token,totalSupply } = await loadFixture(deployTokenFixture);
            const [maxtax,wellatMAx,cooldowmtime] = await token.getLimits();

            console.log(totalSupply * 5n / 1000n);
            console.log(maxtax);
            console.log(wellatMAx);
            console.log(cooldowmtime);


        });

        it("setExcluded",async function () {
            const { token,owner } = await loadFixture(deployTokenFixture);
            
            const temp = await token.isExcludedFromFees(owner.address);
            console.log(temp)


        });






    });

    describe("transfer",function() {
        it("noStart",async function () {
            const { token,owner,user1 } = await loadFixture(deployTokenFixture);
            const amount = ethers.parseEther("100");

            await expect(token.transfer(user1.address,amount)).to.changeTokenBalances(token,[owner,user1],[-amount,amount])

        });
        it("noStart2",async function () {
            const { token,owner,user1,user2 } = await loadFixture(deployTokenFixture);
            const amount = ethers.parseEther("100");

            await token.transfer(user1.address,amount);
            const value = await token.balanceOf(user1.address);
            console.log(value);

            await expect(token.connect(user1).transfer(user2.address,amount)).to.be.revertedWith("Trading not enabled");

            

        });

        it("Start",async function () {
            const { token,owner,user1,user2 } = await loadFixture(deployTokenFixture);
            const amount = ethers.parseEther("1000");

            await token.enableTrading();

            await token.transfer(user1.address,amount);
            const value = await token.balanceOf(user1.address);
            console.log(value);

            await ethers.provider.send("evm_increaseTime", [61]);
            await ethers.provider.send("evm_mine");

            await expect(token.connect(user1).transfer(user2.address,amount)).to.not.be.reverted;

            

        });


    });

    describe("transfer limit",function () {

        it("more than maxtax",async function () {
            const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
            
            await token.enableTrading();
            
            // 先转给user1一些代币
            const max = await token.maxTx();
            await token.transfer(user1.address, max * 3n);
            
            await ethers.provider.send("evm_increaseTime", [61]);
            await ethers.provider.send("evm_mine");
            
            // user1尝试超额转账
            const exceedAmount = max + ethers.parseEther("10");
 
            
            await expect(
                token.connect(user1).transfer(user2.address, exceedAmount)
            ).to.be.revertedWith("Exceeds max transaction amount");

           


        });


        it("more than maxwallet",async function () {
            const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
            
            await token.enableTrading();
            
            const maxWallet = await token.maxWalletAmount();
            
            // 给user2转账达到上限
            await token.transfer(user2.address, maxWallet);
            
            await ethers.provider.send("evm_increaseTime", [61]);
            await ethers.provider.send("evm_mine");
            
            // 给user1一些代币
            await token.transfer(user1.address, ethers.parseEther("1000"));
            
            await ethers.provider.send("evm_increaseTime", [61]);
            await ethers.provider.send("evm_mine");
            
            // user1再次转给user2应该失败
            await expect(
                token.connect(user1).transfer(user2.address, ethers.parseEther("1"))
            ).to.be.revertedWith("Exceeds max wallet amount");
   
        });



        it("start colldowntime",async function () {
            const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
            
            await token.enableTrading();
            
            // 先转给user1一些代币
            
            await token.transfer(user1.address, ethers.parseEther("10000"));


            await token.connect(user1).transfer(user2.address, ethers.parseEther("10"))

            

            await expect(
                token.connect(user1).transfer(user2.address, ethers.parseEther("10"))
            ).to.be.revertedWith("Cooldown period active");

            await ethers.provider.send("evm_increaseTime", [61]);
            await ethers.provider.send("evm_mine");

            await expect(
                token.connect(user1).transfer(user2.address, ethers.parseEther("100"))
            ).to.not.be.reverted;
        });


        it("owner change limit",async function () {
            const { token, totalSupply } = await loadFixture(deployTokenFixture);

            const newMaxTx = totalSupply*10n/1000n;
            const newMaxWalletTx = totalSupply*30n/1000n;

            await token.setLimits(newMaxTx,newMaxWalletTx);
            const [maxTx, maxWallet] = await token.getLimits();
            expect(maxTx).to.equal(newMaxTx);
            expect(maxWallet).to.equal(newMaxWalletTx);


            
        });
        
        it("can mot too low tax",async function () {

            const { token, totalSupply } = await loadFixture(deployTokenFixture);

            const newMaxTx = totalSupply/2000n;
            const newMaxWalletTx = totalSupply/200n;

            await expect(token.setLimits(newMaxTx,newMaxWalletTx )).to.be.revertedWith("max tx too low")
            
        });
        it("owre change islimit",async function () {
            const { token,owner,user1 } = await loadFixture(deployTokenFixture);
            await token.enableTrading();
            await token.setLimitEnable(false);

            const maxwallet =await token.maxWalletAmount();
            const tempAmount = maxwallet+ethers.parseEther("100")

            await expect(token.transfer(user1.address,tempAmount)).to.not.be.reverted;

        });

        
    });

    describe("tax",function () {
        it("settax",async function () {
            const { token } = await loadFixture(deployTokenFixture);
            const newBuytax = 30;
            const newSelltax = 800;
            await token.setTaxRates(newBuytax,newSelltax);


            const [buy1,sell1] = await token.getTaxRates();
            await expect(buy1).to.equal(newBuytax);
            await expect(sell1).to.equal(newSelltax);
        });



        it("not high tax",async function () {
            const { token } = await loadFixture(deployTokenFixture);

            await expect(token.setTaxRates(2000,3000)).to.be.revertedWith("Buy tax too high");
        });

        it("setTaxDistribut",async function () {
            const { token } = await loadFixture(deployTokenFixture);

            await token.setTaxDistribution(5000, 3000, 1000, 1000);
            const [liq, mark, dev, burn] = await token.getTaxDistribution();

            await expect(liq).to.equal(5000);
            await expect(mark).to.equal(3000);
            await expect(dev).to.equal(1000);
            await expect(burn).to.equal(1000);
        });

        it("not totual1000",async function () {
            const { token } = await loadFixture(deployTokenFixture);

            await expect(token.setTaxDistribution(5000, 3000, 1000, 500)).to.be.revertedWith("Shares must sum to 10000");
        });

        it("reflashAddress",async function () {
            const { token,user1, user2, user3 } = await loadFixture(deployTokenFixture);

            await token.setTaxwallet(user1.address,user2.address,user3.address);

            expect(await token.liquidityTaxwallet()).to.equal(user1.address);
            expect(await token.marketingTaxwallet()).to.equal(user2.address);
            expect(await token.devTaxwallet()).to.equal(user3.address);
        });

        

    });

    describe("blacklist",function () {
        it("ower admin",async function () {
            const { token,owner,user1 } = await loadFixture(deployTokenFixture);

            await token.setBlackAddress(user1.address,true);

            expect(await token.isBlacklisted(user1.address)).to.be.true;

        });



        it("can not transfer",async function () {
            const { token,owner,user1,user2  } = await loadFixture(deployTokenFixture);

            await token.enableTrading();

            await token.transfer(user1.address,ethers.parseEther("1200"));

            await token.setBlackAddress(user1.address,true);
            


            await expect(token.connect(user1).transfer(user2.address,ethers.parseEther("500"))).to.be.revertedWith("Blacklisted address");

        });



        it("ower can not in black",async function () {
            const { token,owner,user1,user2  } = await loadFixture(deployTokenFixture);

            await expect(token.setBlackAddress(owner.address,true)).to.be.revertedWith("Cannot blacklist owner");
            expect(await token.isBlacklisted(owner.address)).to.be.false;


        });
    });

    describe("Access Control", function () {
        it("not owner not can1",async function () {
            const { token,owner,user1,user2 } = await loadFixture(deployTokenFixture);

            await expect(token.connect(user1).setTaxRates(100,200)).to.be.reverted;
            


        });

        it("not owner not can2",async function () {
            const { token,owner,user1,user2 } = await loadFixture(deployTokenFixture);

            await expect(token.connect(user1).setLimits(ethers.parseEther("10000"),ethers.parseEther("2000"))).to.be.reverted;
            


        });

        it("not owner not can3",async function () {
            const { token,owner,user1,user2 } = await loadFixture(deployTokenFixture);

            await expect(token.connect(user1).enableTrading()).to.be.reverted;
            


        });

        it("not owner not can4",async function () {
            const { token,owner,user1,user2 } = await loadFixture(deployTokenFixture);

            await expect(token.connect(user1).setBlackAddress(user2.address,true)).to.be.reverted;
            


        });



    });

    describe("trading",async function () {
        it("trading change",async function () {
            const { token } = await loadFixture(deployTokenFixture);

            expect(await token.tradingEnabled()).to.be.false;
            await token.enableTrading();
            expect(await token.tradingEnabled()).to.be.true;

            


        });

        it("trading change can not two times",async function () {
            const { token } = await loadFixture(deployTokenFixture);

            await token.enableTrading()



            
            await expect(token.enableTrading()).to.be.revertedWith("Trading already enabled");

            


        });
    });


    describe("excutin",function () {
        it("ower can set exclutionfees",async function () {
            const { token,user1 } = await loadFixture(deployTokenFixture);

            await token.setExcludedFromFees(user1.address,true);
            expect(await token.isExcludedFromFees(user1.address)).to.be.true;

            await token.setExcludedFromFees(user1.address,false);
            expect(await token.isExcludedFromFees(user1.address)).to.be.false;
        });


        it("ower can set exclutionlims",async function () {
            const { token,user1 } = await loadFixture(deployTokenFixture);

            await token.setExcludedFromLimits(user1.address,true);

            await token.enableTrading();

            const maxWalletAmount = await token.maxWalletAmount();
            const tempAmount = maxWalletAmount + ethers.parseEther("1000");

            await expect(token.transfer(user1.address,tempAmount)).to.not.be.reverted;
            
        });

        



    });

    describe("Edge Cases",function () {
        it("zero address transfer",async function () {
            const { token,user1 } = await loadFixture(deployTokenFixture);
            await expect(token.transfer(ethers.ZeroAddress,ethers.parseEther("1000"))).to.be.reverted;

        });

        it("zero  transfer",async function () {
            const { token,user1 } = await loadFixture(deployTokenFixture);
            await expect(token.transfer(user1.address,0)).to.be.revertedWith("Transfer amount must be greater than zero");

        });

        it("small  transfer",async function () {
            const { token,user1 } = await loadFixture(deployTokenFixture);

            await token.enableTrading();

            const smallamount = 1n;


            await expect(token.transfer(user1.address,smallamount)).to.not.be.reverted;

        });



    });


    describe("gas",function () {
        it("memry gas",async function () {
            const { token,user1 } = await loadFixture(deployTokenFixture);

            await token.enableTrading();
            const tx= await token.transfer(user1.address,ethers.parseEther("1000"));

            const recipt =await tx.wait();
            console.log(`gas ${recipt.gasUsed.toString()}`);
            



        });

    });


   

    



    
});