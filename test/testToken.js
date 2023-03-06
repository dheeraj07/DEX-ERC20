const { ethers } = require("hardhat");
const { expect, use} = require("chai");

const tokens = (inp) => 
{
    return ethers.utils.parseUnits(inp.toString(), "ether");
}

const name = "MyToken";
const symbol =  "MT";
const decimalPlaces = 18;
const value = tokens("10000");

describe("token", () => {

    let token;
    let deployer, user, exchange

    beforeEach(async () => 
    {
        const tokenContract = await ethers.getContractFactory("Token");
        token = await tokenContract.deploy(name, symbol, "10000"); 
        [deployer, user, exchange] = await ethers.getSigners();
    });
    
    describe("Deployment", () => 
    {
        it("It has a name", async() => 
        {
            const tokenName = await token.name();
            expect(tokenName).to.equal(name);
        });

        it("Has Correct Symbol", async () => 
        {
            const symbol = await token.symbol();
            expect(symbol).to.equal(symbol);
        });

        it("Has Correct Decimals", async () => 
        {
            const decimals = await token.decimals();
            expect(decimals).to.equal(decimalPlaces);
        });

        it("Has Correct Total Supply", async () => 
        {
            expect(await token.totalSupply()).to.equal(value);
        });

        it("Has assigned Total Supply to the caller", async () => 
        {
            expect(await token.balanceOf(deployer.address)).to.equal(value);
        });
    });


    describe("TransferTokens", () => 
    {
        let amount,transaction, result;
        beforeEach(async () =>
        {
            amount = tokens(300);
            transaction = await token.connect(deployer).transfer(user.address, amount);
            result = await transaction.wait();
        })


        describe("Success", () => 
        {
            it("Checking the transfer", async()=>
            {
                expect(await token.balanceOf(user.address)).to.equal(amount);
            });

            it("Checking the transaction mining status(event)", async()=>
            {
                const emittedEvent = result.events[0];

                expect(emittedEvent.args._from).to.equal(deployer.address);
                expect(emittedEvent.args._to).to.equal(user.address);
                expect(emittedEvent.args._value).to.equal(amount);
            }); 
        });
        
        describe("Failure", () => 
        {
            it("Sending more than required tokens", async ()=>
            {
                const sendTokens = tokens(100000000);
                await expect(token.connect(deployer).transfer(user.address, sendTokens)).to.be.reverted;
            });

            it("Reject invalid receipent", async ()=>
            {
                const sendTokens = tokens(10000);
                await expect(token.connect(deployer).transfer('0x0000000000000000000000000000000000000000', sendTokens)).to.be.reverted;
            });
        });
    });


    describe("Approving Tokens", () => 
    {
        let amount,transaction, result;

        beforeEach( async()=>
        {
            amount = tokens(100);
            transaction = await token.connect(deployer).approve(exchange.address, amount);
            result = await transaction.wait();
        });

        describe("Success", () => 
        {
            it("Check if allowance is assigned for token spending", async () => 
            {
                expect(await token.allowances(deployer.address, exchange.address)).to.equal(tokens(100));
            });

            it("Check the approaval event logs", async () => 
            {
                const events = result.events[0];

                expect(events.args._owner).to.equal(deployer.address);
                expect(events.args._spender).to.equal(exchange.address);
                expect(events.args._value).to.equal(tokens(100));
            });
        });


        describe("Failure", () => 
        {
            it("Rejects invalid receipent", async ()=>
            {
                const sendTokens = tokens(10000);
                await expect(token.connect(deployer).approve('0x0000000000000000000000000000000000000000', sendTokens)).to.be.reverted;
            });
        });
    });


    describe("Delegated token transfers", () => 
    {
        let amount,transaction, result;

        beforeEach( async()=>
        {
            amount = tokens("100");
            transaction = await token.connect(deployer).approve(exchange.address, amount);
            result = await transaction.wait();
        });

        describe('Success', ()=>
        {
            beforeEach(async () => 
            {
                transaction =  await token.connect(exchange).transferFrom(deployer.address,user.address, amount);
                result = await transaction.wait();
            });

            it("Check transfer",async () => 
            {
                expect(await token.balanceOf(deployer.address)).to.equal(tokens("9900"));
            });

            it("Resets the token allowance",async () => 
            {
                expect(await token.allowances(deployer.address, exchange.address)).to.equal(0);
            });

            it("Emit a transfer event", async()=>
            {
                const emittedEvent = result.events[0];

                expect(emittedEvent.args._from).to.equal(deployer.address);
                expect(emittedEvent.args._to).to.equal(user.address);
                expect(emittedEvent.args._value).to.equal(amount);
            }); 
        });


        describe('Failure', ()=>
        {
            it("Invalid transfer", async () => 
            {
                const invalidAmount = "10000";
                expect(await token.connect(exchange).transferFrom(deployer.address, user.address, invalidAmount)).to.be.reverted;
            });
        });
    });
    
    
});