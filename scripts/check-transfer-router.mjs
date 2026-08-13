import assert from "node:assert/strict";
import hre from "hardhat";

const connection = await hre.network.create();
const { ethers } = connection;
const [admin, sender, recipient, treasury, outsider] =
  await ethers.getSigners();

const Token = await ethers.getContractFactory("TucuToken");
const token = await Token.deploy();
await token.waitForDeployment();

const Proxy = await ethers.getContractFactory("TucuProxy");
const proxy = await Proxy.deploy(await token.getAddress(), admin.address);
await proxy.waitForDeployment();
const tucu = Token.attach(await proxy.getAddress());

const Router = await ethers.getContractFactory("TucuTransferRouter");
const router = await Router.deploy(admin.address, treasury.address, 50);
await router.waitForDeployment();
await router.setTokenAllowed(await proxy.getAddress(), true);

await tucu.mint(sender.address, ethers.parseEther("100"));
await tucu
  .connect(sender)
  .approve(await router.getAddress(), ethers.parseEther("10"));
await router
  .connect(sender)
  .routeToken(
    await proxy.getAddress(),
    recipient.address,
    ethers.parseEther("10"),
  );

assert.equal(
  await tucu.balanceOf(recipient.address),
  ethers.parseEther("9.95"),
);
assert.equal(
  await tucu.balanceOf(treasury.address),
  ethers.parseEther("0.05"),
);
assert.equal(await tucu.balanceOf(await router.getAddress()), 0n);

await assert.rejects(
  router
    .connect(outsider)
    .setFeeBps(100),
);
await assert.rejects(router.setFeeBps(101));
await router.pause();
await assert.rejects(
  router
    .connect(sender)
    .routeToken(
      await proxy.getAddress(),
      recipient.address,
      ethers.parseEther("1"),
    ),
);

console.log("TUCU_TRANSFER_ROUTER_CHECK_OK", await router.getAddress());
