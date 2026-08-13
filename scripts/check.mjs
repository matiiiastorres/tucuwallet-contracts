import assert from "node:assert/strict";
import hre from "hardhat";
import { upgrades } from "@openzeppelin/hardhat-upgrades";

const ADMIN = "0xa2318a8C5A19bbed1176B6cA2a760A9C895f17c9";
const connection = await hre.network.create();
const { ethers } = connection;
const upgradesApi = await upgrades(hre, connection);

const [deployer, recipient, outsider] = await ethers.getSigners();
const Token = await ethers.getContractFactory("TucuToken");
const token = await upgradesApi.deployProxy(Token, [ADMIN], { kind: "uups" });
await token.waitForDeployment();

assert.equal(await token.name(), "Tucu");
assert.equal(await token.symbol(), "TUCU");
assert.equal(await token.totalSupply(), 0n);
assert.equal(await token.maxSupply(), ethers.parseEther("100000000"));

const minterRole = await token.MINTER_ROLE();
const pauserRole = await token.PAUSER_ROLE();
const upgraderRole = await token.UPGRADER_ROLE();
assert.equal(await token.hasRole(minterRole, ADMIN), true);
assert.equal(await token.hasRole(pauserRole, ADMIN), true);
assert.equal(await token.hasRole(upgraderRole, ADMIN), true);

// Give the local deployer temporary roles only inside this isolated test chain.
const adminRole = await token.DEFAULT_ADMIN_ROLE();
await connection.provider.send("hardhat_impersonateAccount", [ADMIN]);
await connection.provider.send("hardhat_setBalance", [ADMIN, "0x56BC75E2D63100000"]);
const admin = await ethers.getSigner(ADMIN);
await token.connect(admin).grantRole(minterRole, deployer.address);
await token.connect(admin).grantRole(pauserRole, deployer.address);

await token.mint(recipient.address, ethers.parseEther("250"));
assert.equal(await token.balanceOf(recipient.address), ethers.parseEther("250"));

await token.pause();
await assert.rejects(token.connect(recipient).transfer(outsider.address, 1n));
await token.unpause();

await token.connect(recipient).burn(ethers.parseEther("50"));
assert.equal(await token.balanceOf(recipient.address), ethers.parseEther("200"));
assert.equal(await token.totalSupply(), ethers.parseEther("200"));

await token.connect(admin).setMaxSupply(ethers.parseEther("200"));
await assert.rejects(token.mint(recipient.address, 1n));
await assert.rejects(token.connect(outsider).mint(outsider.address, 1n));

console.log("TUCU_CHECK_OK", await token.getAddress());
