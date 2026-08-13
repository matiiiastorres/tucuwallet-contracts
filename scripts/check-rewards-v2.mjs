import assert from "node:assert/strict";
import hre from "hardhat";

const connection = await hre.network.create();
const { ethers } = connection;
const [admin, rewardSigner, recipient, outsider] = await ethers.getSigners();

const Token = await ethers.getContractFactory("TucuToken");
const token = await Token.deploy();
await token.waitForDeployment();

const Proxy = await ethers.getContractFactory("TucuProxy");
const proxy = await Proxy.deploy(
  await token.getAddress(),
  admin.address,
);
await proxy.waitForDeployment();
const tucu = Token.attach(await proxy.getAddress());

const Distributor = await ethers.getContractFactory("RewardsDistributorV2");
const distributor = await Distributor.deploy(
  await proxy.getAddress(),
  admin.address,
  rewardSigner.address,
);
await distributor.waitForDeployment();

const minterRole = await tucu.MINTER_ROLE();
await tucu.grantRole(minterRole, await distributor.getAddress());

const welcomeMission = ethers.id("web3_welcome");
await distributor.configureMission(
  welcomeMission,
  ethers.parseEther("1"),
  0,
  1,
  1,
  true,
);

async function signClaim({
  signer = rewardSigner,
  wallet = recipient.address,
  missionId = welcomeMission,
  claimId = ethers.id(`claim-${crypto.randomUUID()}`),
  amount = ethers.parseEther("1"),
  deadline = Math.floor(Date.now() / 1000) + 600,
} = {}) {
  const network = await ethers.provider.getNetwork();
  const domain = {
    name: "TucuRewardsDistributor",
    version: "2",
    chainId: network.chainId,
    verifyingContract: await distributor.getAddress(),
  };
  const types = {
    RewardClaim: [
      { name: "recipient", type: "address" },
      { name: "missionId", type: "bytes32" },
      { name: "claimId", type: "bytes32" },
      { name: "amount", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };
  const value = { recipient: wallet, missionId, claimId, amount, deadline };
  const signature = await signer.signTypedData(domain, types, value);
  return { ...value, signature };
}

const firstClaim = await signClaim();
await distributor
  .connect(recipient)
  .claim(
    firstClaim.missionId,
    firstClaim.claimId,
    firstClaim.recipient,
    firstClaim.amount,
    firstClaim.deadline,
    firstClaim.signature,
  );
assert.equal(await tucu.balanceOf(recipient.address), ethers.parseEther("1"));

await assert.rejects(
  distributor
    .connect(recipient)
    .claim(
      firstClaim.missionId,
      firstClaim.claimId,
      firstClaim.recipient,
      firstClaim.amount,
      firstClaim.deadline,
      firstClaim.signature,
    ),
);

const secondWelcome = await signClaim();
await assert.rejects(
  distributor
    .connect(recipient)
    .claim(
      secondWelcome.missionId,
      secondWelcome.claimId,
      secondWelcome.recipient,
      secondWelcome.amount,
      secondWelcome.deadline,
      secondWelcome.signature,
    ),
);

const outsiderClaim = await signClaim({ wallet: outsider.address });
await assert.rejects(
  distributor
    .connect(recipient)
    .claim(
      outsiderClaim.missionId,
      outsiderClaim.claimId,
      outsiderClaim.recipient,
      outsiderClaim.amount,
      outsiderClaim.deadline,
      outsiderClaim.signature,
    ),
);

const invalidSignerClaim = await signClaim({
  signer: outsider,
  wallet: outsider.address,
});
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      invalidSignerClaim.missionId,
      invalidSignerClaim.claimId,
      invalidSignerClaim.recipient,
      invalidSignerClaim.amount,
      invalidSignerClaim.deadline,
      invalidSignerClaim.signature,
  ),
);

const changedAmountClaim = await signClaim({
  wallet: outsider.address,
  amount: ethers.parseEther("2"),
});
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      changedAmountClaim.missionId,
      changedAmountClaim.claimId,
      changedAmountClaim.recipient,
      changedAmountClaim.amount,
      changedAmountClaim.deadline,
      changedAmountClaim.signature,
  ),
);

await assert.rejects(
  distributor
    .connect(outsider)
    .configureMission(ethers.ZeroHash, 1n, 0, 1, 1, true),
);
await assert.rejects(
  distributor.configureMission(
    ethers.id("too_large"),
    ethers.parseEther("101"),
    0,
    1,
    1,
    true,
  ),
);

const expiredClaim = await signClaim({
  wallet: outsider.address,
  deadline: Math.floor(Date.now() / 1000) - 60,
});
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      expiredClaim.missionId,
      expiredClaim.claimId,
      expiredClaim.recipient,
      expiredClaim.amount,
      expiredClaim.deadline,
      expiredClaim.signature,
    ),
);

const malformedClaim = await signClaim({ wallet: outsider.address });
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      malformedClaim.missionId,
      malformedClaim.claimId,
      malformedClaim.recipient,
      malformedClaim.amount,
      malformedClaim.deadline,
      "0x1234",
    ),
);

const disabledMission = ethers.id("disabled");
await distributor.configureMission(
  disabledMission,
  ethers.parseEther("1"),
  0,
  1,
  1,
  false,
);
const disabledClaim = await signClaim({
  wallet: outsider.address,
  missionId: disabledMission,
});
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      disabledClaim.missionId,
      disabledClaim.claimId,
      disabledClaim.recipient,
      disabledClaim.amount,
      disabledClaim.deadline,
      disabledClaim.signature,
    ),
);

const cooldownMission = ethers.id("cooldown");
await distributor.configureMission(
  cooldownMission,
  ethers.parseEther("1"),
  3600,
  0,
  0,
  true,
);
const cooldownFirst = await signClaim({
  wallet: admin.address,
  missionId: cooldownMission,
});
await distributor
  .connect(admin)
  .claim(
    cooldownFirst.missionId,
    cooldownFirst.claimId,
    cooldownFirst.recipient,
    cooldownFirst.amount,
    cooldownFirst.deadline,
    cooldownFirst.signature,
  );
const cooldownSecond = await signClaim({
  wallet: admin.address,
  missionId: cooldownMission,
});
await assert.rejects(
  distributor
    .connect(admin)
    .claim(
      cooldownSecond.missionId,
      cooldownSecond.claimId,
      cooldownSecond.recipient,
      cooldownSecond.amount,
      cooldownSecond.deadline,
      cooldownSecond.signature,
    ),
);

const sixtyMission = ethers.id("sixty");
const fiftyMission = ethers.id("fifty");
await distributor.configureMission(
  sixtyMission,
  ethers.parseEther("60"),
  0,
  1,
  1,
  true,
);
await distributor.configureMission(
  fiftyMission,
  ethers.parseEther("50"),
  0,
  1,
  1,
  true,
);
const sixtyClaim = await signClaim({
  wallet: outsider.address,
  missionId: sixtyMission,
  amount: ethers.parseEther("60"),
});
await distributor
  .connect(outsider)
  .claim(
    sixtyClaim.missionId,
    sixtyClaim.claimId,
    sixtyClaim.recipient,
    sixtyClaim.amount,
    sixtyClaim.deadline,
    sixtyClaim.signature,
  );
const fiftyClaim = await signClaim({
  wallet: outsider.address,
  missionId: fiftyMission,
  amount: ethers.parseEther("50"),
});
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      fiftyClaim.missionId,
      fiftyClaim.claimId,
      fiftyClaim.recipient,
      fiftyClaim.amount,
      fiftyClaim.deadline,
      fiftyClaim.signature,
    ),
);

const signerRole = await distributor.REWARD_SIGNER_ROLE();
await distributor.revokeRole(signerRole, rewardSigner.address);
const revokedSignerClaim = await signClaim({
  wallet: outsider.address,
  missionId: fiftyMission,
  amount: ethers.parseEther("50"),
});
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      revokedSignerClaim.missionId,
      revokedSignerClaim.claimId,
      revokedSignerClaim.recipient,
      revokedSignerClaim.amount,
      revokedSignerClaim.deadline,
      revokedSignerClaim.signature,
    ),
);

await distributor.pause();
const pausedClaim = await signClaim({ wallet: outsider.address });
await assert.rejects(
  distributor
    .connect(outsider)
    .claim(
      pausedClaim.missionId,
      pausedClaim.claimId,
      pausedClaim.recipient,
      pausedClaim.amount,
      pausedClaim.deadline,
      pausedClaim.signature,
    ),
);

console.log("REWARDS_DISTRIBUTOR_V2_CHECK_OK", await distributor.getAddress());
