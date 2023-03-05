const { ethers } = require("hardhat");
const { expect} = require("chai");

const tokens = (inp) => 
{
    return ethers.utils.parseUnits(inp.toString(), "ether");
}

describe("Exchange", () => {

    let deployer, feeAccount, exchangeContractDeployed, trader1, trader2, trader3, deployedToken1, deployedToken2;
    const feePercent = 10;

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

        describe("success", () => 
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

        describe("failure", () => 
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
        
        describe("success", () => 
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

        describe("failure", () => 
        {
            it("Check if withdrawal is possible without any deposit", async () => 
            {
                await expect(exchangeContractDeployed.connect(trader1).withdrawTokens(deployedToken1.address, amount)).revertedWith("Insufficient balance.");
            });
        });
    });


    describe("Orders", () => 
    {
        let transaction, amount = tokens(100), response;
        describe("success", () => 
        {
            beforeEach(async() => 
            {
                await deployedToken1.connect(deployer).transfer(trader1.address, amount);
                await deployedToken1.connect(trader1).approve(exchangeContractDeployed.address, amount);
                await exchangeContractDeployed.connect(trader1).depositToken(deployedToken1.address, amount);

                transaction = await exchangeContractDeployed.connect(trader1).makeOrder(deployedToken2.address, deployedToken1.address, amount, amount);
                response = await transaction.wait();
            });

            it("Check if the order event is emitted", () => 
            {
                const event = response.events[0];
                expect(event.args._orderId).to.equal(1);
                expect(event.args._trader).to.equal(trader1.address);
                expect(event.args._tokenBuy).to.equal(deployedToken2.address);
                expect(event.args._tokenSell).to.equal(deployedToken1.address);
                expect(event.args._amountBuy).to.equal(amount);
                expect(event.args._amountSell).to.equal(amount);
            });

        });

        describe("Failure", () => 
        {
            it("Rejects placing an order due to insufficient balance", async () => 
            {
                await expect(exchangeContractDeployed.connect(trader2).makeOrder(deployedToken2.address, deployedToken1.address, amount, amount)).revertedWith("Insufficient balance.");
            });
        });
    });


    describe("Order Actions", () => 
    {
        let transaction, amount = tokens(1), response;
        beforeEach(async() => 
        {
            await deployedToken1.connect(deployer).transfer(trader1.address, amount);
            await deployedToken1.connect(trader1).approve(exchangeContractDeployed.address, amount);
            await exchangeContractDeployed.connect(trader1).depositToken(deployedToken1.address, amount);

            transaction = await exchangeContractDeployed.connect(trader1).makeOrder(deployedToken2.address, deployedToken1.address, amount, amount);
            response = await transaction.wait();
        });

        describe("Cancelling Orders", () =>
        {
            describe("Success", () => 
            {
                beforeEach(async() => 
                {
                    transaction = await exchangeContractDeployed.connect(trader1).cancelOrder(1);
                    response = await transaction.wait();
                });

                it("check if the order is successfully cancelled", async () => 
                {
                    expect(await exchangeContractDeployed.ordersCancelled(1)).to.equal(true);
                });

                it("Check if the cancel event is emitted", async() => 
                {
                    const event = response.events[0];

                    expect(event.args._orderId).to.equal(1);
                    expect(event.args._trader).to.equal(trader1.address);
                    expect(event.args._tokenBuy).to.equal(deployedToken2.address);
                    expect(event.args._tokenSell).to.equal(deployedToken1.address);
                    expect(event.args._amountBuy).to.equal(amount);
                    expect(event.args._amountSell).to.equal(amount);
                }); 
            });

            describe("Failure", () => 
            {
                it("check if only the real order owner is able to cancel the order", async () => 
                {
                    await expect(exchangeContractDeployed.cancelOrder(1)).revertedWith("Insufficient privileages.");
                });

                it("Rejects invalid order_id's", async () => 
                {
                    await expect(exchangeContractDeployed.cancelOrder(18)).revertedWith("Invalid trade order.");
                });
            });
        });


        describe("Filling Orders", () => 
        {   
            beforeEach(async() => 
            {
                await deployedToken2.connect(deployer).transfer(trader2.address, tokens(3));
                await deployedToken2.connect(trader2).approve(exchangeContractDeployed.address,  tokens(3));
                await exchangeContractDeployed.connect(trader2).depositToken(deployedToken2.address,  tokens(3));
            });
            describe("Success", () => 
            {
                beforeEach(async() => 
                {
                    transaction = await exchangeContractDeployed.connect(trader2).fillOrder("1");
                    response = await transaction.wait();
                });
               it("Check if the order is successfully execited", async () => 
               {
                    expect(await exchangeContractDeployed.balanceOf(deployedToken1.address, trader1.address)).equal(tokens(0));
                    expect(await exchangeContractDeployed.balanceOf(deployedToken1.address, trader2.address)).equal(tokens(1));
                    expect(await exchangeContractDeployed.balanceOf(deployedToken1.address, feeAccount.address)).equal(tokens(0));

                    expect(await exchangeContractDeployed.balanceOf(deployedToken2.address, trader1.address)).equal(tokens(1));
                    expect(await exchangeContractDeployed.balanceOf(deployedToken2.address, trader2.address)).equal(tokens(1.9));
                    expect(await exchangeContractDeployed.balanceOf(deployedToken2.address, feeAccount.address)).equal(tokens(0.1)); 
               });

               it("Check if the trade event is emitted", async() => 
                {
                    const event = response.events[0];

                    expect(event.args._orderId).to.equal(1);
                    expect(event.args._orderMaker).to.equal(trader1.address);
                    expect(event.args._orderTaker).to.equal(trader2.address);
                    expect(event.args._tokenBuy).to.equal(deployedToken2.address);
                    expect(event.args._tokenSell).to.equal(deployedToken1.address);
                    expect(event.args._amountBuy).to.equal(tokens(1));
                    expect(event.args._amountSell).to.equal(tokens(1));
                    expect(event.args._feeAmount).to.equal(tokens(0.1));
                });

                it("Check for the filled Orders", async() =>
                {
                    expect(await exchangeContractDeployed.ordersFilled("1")).to.equal(true);
                });
            });

            describe("Failure", () => 
            {
                it("Check for invalid Orders", async () => 
                {
                    await expect(exchangeContractDeployed.connect(trader2).fillOrder(99)).revertedWith("Invalid Order.");
                });

                it("Check for filled Orders", async () => 
                {
                    await exchangeContractDeployed.connect(trader2).fillOrder(1);
                    await expect(exchangeContractDeployed.connect(trader2).fillOrder(1)).revertedWith("Order is filled already.");
                });

                it("Check for cancelled Orders", async () => 
                {
                    await exchangeContractDeployed.connect(trader1).cancelOrder(1);
                    await expect(exchangeContractDeployed.connect(trader2).fillOrder(1)).revertedWith("Order is cancelled.");
                });

            });
        });
    });  
});