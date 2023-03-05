const { ethers } = require("hardhat");

async function main() {
    const Token = await ethers.getContractFactory("Token");
    const deployedCon = await Token.deploy();

    await deployedCon.deployed();
    console.log(`Contract address: + ${deployedCon.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors. 
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
