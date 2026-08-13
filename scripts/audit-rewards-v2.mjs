import assert from "node:assert/strict";
import fs from "node:fs/promises";
import hre from "hardhat";

const TOKEN_ADDRESS =
  process.env.TUCU_TOKEN_ADDRESS ||
  "0x2dCFE82458e2dc32E1035c6F6535B496B04Ab3a3";
const DISTRIBUTOR_ADDRESS = process.env.TUCU_REWARDS_DISTRIBUTOR_ADDRESS;
const ADMIN_ADDRESS = process.env.TUCU_ADMIN_ADDRESS;
const REWARD_SIGNER_ADDRESS = process.env.TUCU_REWARD_SIGNER_ADDRESS;

if (!DISTRIBUTOR_ADDRESS || !ADMIN_ADDRESS || !REWARD_SIGNER_ADDRESS) {
  throw new Error(
    "Define TUCU_REWARDS_DISTRIBUTOR_ADDRESS, TUCU_ADMIN_ADDRESS y TUCU_REWARD_SIGNER_ADDRESS.",
  );
}

const connection = await hre.network.connect();
const { ethers } = connection;
const network = await ethers.provider.getNetwork();
assert.equal(network.chainId, 480n, "La auditoria debe ejecutarse en chainId 480.");

for (const address of [
  TOKEN_ADDRESS,
  DISTRIBUTOR_ADDRESS,
  ADMIN_ADDRESS,
  REWARD_SIGNER_ADDRESS,
]) {
  assert.ok(ethers.isAddress(address), `Direccion invalida: ${address}`);
}
assert.notEqual(
  ADMIN_ADDRESS.toLowerCase(),
  REWARD_SIGNER_ADDRESS.toLowerCase(),
  "El firmante de recompensas debe estar separado del administrador.",
);
assert.notEqual(
  await ethers.provider.getCode(TOKEN_ADDRESS),
  "0x",
  "El proxy TUCU no tiene codigo.",
);
assert.notEqual(
  await ethers.provider.getCode(DISTRIBUTOR_ADDRESS),
  "0x",
  "El distribuidor no tiene codigo.",
);

const token = await ethers.getContractAt("TucuToken", TOKEN_ADDRESS);
const distributor = await ethers.getContractAt(
  "RewardsDistributorV2",
  DISTRIBUTOR_ADDRESS,
);
assert.equal(
  (await distributor.token()).toLowerCase(),
  TOKEN_ADDRESS.toLowerCase(),
  "El distribuidor apunta a otro token.",
);
assert.equal(await distributor.paused(), false, "El distribuidor esta pausado.");
assert.equal(
  await token.hasRole(await token.MINTER_ROLE(), DISTRIBUTOR_ADDRESS),
  true,
  "El distribuidor no tiene MINTER_ROLE en TUCU.",
);
assert.equal(
  await distributor.hasRole(
    await distributor.DEFAULT_ADMIN_ROLE(),
    ADMIN_ADDRESS,
  ),
  true,
  "El administrador no tiene DEFAULT_ADMIN_ROLE.",
);
assert.equal(
  await distributor.hasRole(await distributor.PAUSER_ROLE(), ADMIN_ADDRESS),
  true,
  "El administrador no tiene PAUSER_ROLE.",
);
assert.equal(
  await distributor.hasRole(
    await distributor.REWARD_SIGNER_ROLE(),
    REWARD_SIGNER_ADDRESS,
  ),
  true,
  "El backend signer no tiene REWARD_SIGNER_ROLE.",
);
assert.equal(
  await distributor.MAX_REWARD_PER_WINDOW(),
  ethers.parseEther("100"),
  "El limite global no es 100 TUCU.",
);

const missions = JSON.parse(
  await fs.readFile("config/rewards-v2-missions.json", "utf8"),
);
for (const mission of missions) {
  const configured = await distributor.missions(ethers.id(mission.id));
  assert.equal(
    configured.amount,
    ethers.parseEther(String(mission.amountTucu)),
    `${mission.id}: amount`,
  );
  assert.equal(
    configured.cooldown,
    BigInt(mission.cooldownSeconds),
    `${mission.id}: cooldown`,
  );
  assert.equal(
    configured.maxLifetimeClaims,
    BigInt(mission.maxLifetimeClaims),
    `${mission.id}: lifetime`,
  );
  assert.equal(
    configured.maxClaimsPerWindow,
    BigInt(mission.maxClaimsPer30Days),
    `${mission.id}: window`,
  );
  assert.equal(configured.enabled, true, `${mission.id}: disabled`);
}

const testFunding = await distributor.missions(
  ethers.id("test_wallet_funding"),
);
assert.equal(
  testFunding.enabled,
  false,
  "La mision privada test_wallet_funding no debe estar habilitada.",
);

console.log(
  JSON.stringify(
    {
      status: "REWARDS_DISTRIBUTOR_V2_AUDIT_OK",
      chainId: Number(network.chainId),
      token: TOKEN_ADDRESS,
      distributor: DISTRIBUTOR_ADDRESS,
      admin: ADMIN_ADDRESS,
      rewardSigner: REWARD_SIGNER_ADDRESS,
      missions: missions.length,
      maxRewardPer30Days: "100 TUCU",
    },
    null,
    2,
  ),
);
