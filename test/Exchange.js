const { ethers } = require("hardhat");
const { expect} = require("chai");
const { result } = require("lodash");

const tokens = (inp) => 
{
    return ethers.utils.parseUnits(inp.toString(), "ether");
}

describe("Exchange", () => {

    let deployer, feeAccount, exchangeContractDeployed, trader1, trader2, trader3, deployedToken1, deployedToken2;
    const feePercent = tokens(10);

    beforeEach(async () => 
    {
        [deployer, feeAccount, trader1, trader2, trader3] = await ethers.getSigners();
        const exchangeContract = await ethers.getContractFactory("Exchange");
        const tokenContract = await ethers.getContractFactory("TokenOZ");
        
        deployedToken1 = await tokenContract.deploy("10000"); 
        deployedToken2 = await tokenContract.deploy("10000"); 

        exchangeContractDeployed = await exchangeContract.deploy(feeAccount.address, feePercent);
        
    });
    
    describe("Deployment", () => 
    {
        it("Check the fee acount of the exchange", async() => 
        {
            expect(await exchangeContractDeployed.feeAccount()).to.equal(feeAccount.address);
        });

        it("Check the fee percent of the exchange", async() => 
        {
            expect(await exchangeContractDeployed.feePercent()).to.equal(feePercent);
        });
    });
    
    describe("Deposits", () => 
    {
        let transaction, amount = tokens(100), response;

        describe("Success", () => 
        {
            beforeEach(async () => 
            {
                await deployedToken1.connect(deployer).transfer(trader1.address, amount);
                await deployedToken1.connect(trader1).approve(exchangeContractDeployed.address, amount);
                transaction = await exchangeContractDeployed.connect(trader1).depositToken(deployedToken1.address, amount);
                response = await transaction.wait();
            });

              it("Check if the trader's deposit is successful", async () => 
              {
                expect(await exchangeContractDeployed.balanceOf(deployedToken1.address, trader1.address)).to.equal(amount);
              });

              it("Check if the deposit event is emitted", async () => 
              {
                const event = response.events[2];
                
                expect(event.args._tokenAddress).to.equal(deployedToken1.address);
                expect(event.args._userAddress).to.equal(trader1.address);
                expect(event.args._amount).to.equal(amount);
              });
        });

        describe("Failure", () => 
        {
            it("Deposit without enough balance", async () => 
            {
                await expect(exchangeContractDeployed.connect(trader1).depositToken(deployedToken1.address, amount)).revertedWith("Insufficient balance.");
            });

            it("Deposit without token approval", async () => 
            {
                await deployedToken1.connect(deployer).transfer(trader1.address, amount);
                await expect(exchangeContractDeployed.connect(trader1).depositToken(deployedToken1.address, amount)).revertedWith("Insufficient allowance.");
            });
        });
    });


    describe("Withdraw", () => 
    {
        let transaction, amount = tokens(100), response;
        
        describe("Success", () => 
        {
            beforeEach(async () => 
            {
                await deployedToken1.connect(deployer).transfer(trader1.address, amount);
                await deployedToken1.connect(trader1).approve(exchangeContractDeployed.address, amount);
                await exchangeContractDeployed.connect(trader1).depositToken(deployedToken1.address, amount);
            });

              it("Check if the trader's deposit can be successfully withdrawn", async () => 
              {
                await exchangeContractDeployed.connect(trader1).withdrawTokens(deployedToken1.address, amount)
                expect(await deployedToken1.balanceOf(trader1.address)).to.equal(amount);
              });

              it("Check if the trader's deposit can be successfully withdrawn to a third party address", async () => 
              {
                await exchangeContractDeployed.connect(trader1).withdrawToThirdParty(deployedToken1.address, trader2.address, amount);
                expect(await deployedToken1.balanceOf(trader2.address)).to.equal(amount);
              });

              it("Check if the withdraw event is emitted", async() => 
              {
                transaction = await exchangeContractDeployed.connect(trader1).withdrawTokens(deployedToken1.address, amount)
                response = await transaction.wait();
                const event = response.events[1];
                
                expect(event.args._tokenAddress).to.equal(deployedToken1.address);
                expect(event.args._receiverAddress).to.equal(trader1.address);
                expect(event.args._amount).to.equal(amount);
              });
        });

        describe("Failure", () => 
        {
            it("Check if withdrawal is possible without any deposit", async () => 
            {
                await expect(exchangeContractDeployed.connect(trader1).withdrawTokens(deployedToken1.address, amount)).revertedWith("Insufficient balance.");
            });
        });
    });

    describe("Market Setup",() => 
    {
        describe("Success", () => 
        {
            it("Check if a new market is successfully create", async () => 
            {
                const parentTokenSymbol = "MINA", tradeTokenSymbol = "USDT";
                await exchangeContractDeployed.connect(deployer).RegisterMarket(deployedToken1.address, deployedToken2.address, parentTokenSymbol, tradeTokenSymbol);

                expect(await exchangeContractDeployed.isMarketEnabled(parentTokenSymbol+tradeTokenSymbol)).to.equal(true);
            });
        });

        describe("Failure", () => 
        {
            it("Check if a new market creation is reverted if the creator is not the exchange owner", async () => 
            {
                const parentTokenSymbol = "MINA", tradeTokenSymbol = "USDT";

                await expect(exchangeContractDeployed.connect(trader1).RegisterMarket(deployedToken1.address, deployedToken2.address, parentTokenSymbol, tradeTokenSymbol)).revertedWith("Ownable: caller is not the owner");
            });
        });
    });

    describe("Order Types", () => 
    {
        let transaction, amount = tokens(100), response;
        beforeEach(async() => 
        {
            await deployedToken1.connect(deployer).transfer(trader1.address, amount);
            await deployedToken1.connect(trader1).approve(exchangeContractDeployed.address, amount);
            await exchangeContractDeployed.connect(trader1).depositToken(deployedToken1.address, amount);
            await exchangeContractDeployed.connect(deployer).RegisterMarket(deployedToken1.address, deployedToken2.address, "MINA", "USDT");
        });

        describe("Limit Order", () => 
        {
            describe("Success", () => 
            {
                beforeEach(async() => 
                {
                    await deployedToken2.connect(deployer).transfer(trader2.address, amount);
                    await deployedToken2.connect(trader2).approve(exchangeContractDeployed.address,  amount);
                    await exchangeContractDeployed.connect(trader2).depositToken(deployedToken2.address,  amount);
                });
    
                it("Check if the limit sell order is getting placed", async () => 
                {
                    await exchangeContractDeployed.connect(trader1).limitOrder(tokens(15), tokens(8), 1, "MINAUSDT");
                    
                    expect(await exchangeContractDeployed.connect(deployer).getOrderBookLength(1, "MINAUSDT")).to.equal(1);
                });

                it("Check if the limit buy order is getting placed", async () => 
                {
                    await exchangeContractDeployed.connect(trader2).limitOrder(tokens(10), tokens(2), 0, "MINAUSDT");
                    
                    expect(await exchangeContractDeployed.connect(deployer).getOrderBookLength(0, "MINAUSDT")).to.equal(1);
                });

                it("Check if the order event is emitted", async () => 
                {
                    transaction = await exchangeContractDeployed.connect(trader1).limitOrder(tokens(15),tokens(8), 1, "MINAUSDT");
                    response = await transaction.wait();

                    const events = response.events;

                    expect(events[0].event).to.equal("OrderBookEve");
                    expect(events[1].event).to.equal("OrderEve");
                });
            });

            describe("Failure", () => 
            {
                it("Check if the limit buy order is getting rejected if it is placed without token balance", async () => 
                {
                    await expect(exchangeContractDeployed.connect(trader1).limitOrder(tokens(15), tokens(8), 0, "MINAUSDT")).revertedWith("Insufficient balance.");
                });

                it("Check if the limit sell order is getting rejected if it is placed without token balance", async () => 
                {
                    await expect(exchangeContractDeployed.connect(trader2).limitOrder(tokens(8), tokens(8), 1, "MINAUSDT")).revertedWith("Insufficient balance.");
                });

                it("Check if only the valid markets are allowed for trading", async () => 
                {
                    await expect(exchangeContractDeployed.connect(trader2).limitOrder(tokens(8), tokens(8), 1, "ETHUSDT")).revertedWith("Invalid Market Specified.");
                });
            });
        });


        describe("Market Order", async () => 
        {
            describe("Success", () => 
            {
                beforeEach( async () => 
                {
                    await deployedToken2.connect(deployer).transfer(trader2.address, amount);
                    await deployedToken2.connect(trader2).approve(exchangeContractDeployed.address, amount);
                    await exchangeContractDeployed.connect(trader2).depositToken(deployedToken2.address, amount);

                    await exchangeContractDeployed.connect(trader2).limitOrder(tokens(8), tokens(3), 0, "MINAUSDT");                    
                    await exchangeContractDeployed.connect(trader1).limitOrder(tokens(17), tokens(9), 1, "MINAUSDT");
                    await exchangeContractDeployed.connect(trader1).limitOrder(tokens(10), tokens(2), 1, "MINAUSDT");
                });
                it("Check if the market sell order is getting placed and removed from the order book once fullfilled", async () => 
                {
                    await exchangeContractDeployed.connect(trader1).marketOrder(tokens(8), 1, "MINAUSDT");
                    
                    expect(await exchangeContractDeployed.connect(deployer).getOrderBookLength(0, "MINAUSDT")).to.equal(0);
                });

                it("Check if the market buy order is getting placed and removed from the order book once fullfilled", async () => 
                {
                    await exchangeContractDeployed.connect(trader2).marketOrder(tokens(10), 0, "MINAUSDT");

                    expect(await exchangeContractDeployed.connect(deployer).getOrderBookLength(1, "MINAUSDT")).to.equal(1);
                });

                it("Check if the order event is emitted", async () => 
                {
                    transaction = await exchangeContractDeployed.connect(trader2).marketOrder(tokens(10), 0, "MINAUSDT");
                    response = await transaction.wait();

                    const events = response.events;
                    expect(events[0].event).to.equal("TradeEve");
                });
    
                it("Check the market order", async () => 
                {
                    transaction = await exchangeContractDeployed.connect(trader1).limitOrder(tokens(10), tokens(16), 1, "MINAUSDT");
                    transaction = await exchangeContractDeployed.connect(trader1).limitOrder(tokens(5), tokens(10), 1, "MINAUSDT");
                    transaction = await exchangeContractDeployed.connect(trader1).limitOrder(tokens(2), tokens(12), 1, "MINAUSDT");
                });
    
            });

            describe("Failure", () => 
            {
                it("Check if the market buy order is getting rejected if it is placed without token balance", async () => 
                {
                    await expect(exchangeContractDeployed.connect(trader1).marketOrder(tokens(15), 0, "MINAUSDT")).revertedWith("Insufficient balance.");
                });

                it("Check if the market sell order is getting rejected if it is placed without token balance", async () => 
                {
                    await expect(exchangeContractDeployed.connect(trader2).marketOrder(tokens(26), 1, "MINAUSDT")).revertedWith("Insufficient balance.");
                });

                it("Check if only the valid markets are allowed for trading", async () => 
                {
                    await expect(exchangeContractDeployed.connect(trader2).marketOrder(tokens(8), 1, "ETHUSDT")).revertedWith("Invalid Market Specified.");
                });
            });
        });
        
    })
});