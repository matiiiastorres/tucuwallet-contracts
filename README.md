# TucuWallet Contracts

Production smart contracts used by the TucuWallet Mini App on World Chain
Mainnet (`chainId 480`). This repository is the review surface for World and
contains no application secrets or private keys.

## Production contracts

| Component | Address | Purpose |
| --- | --- | --- |
| TUCU token proxy | `0x2dCFE82458e2dc32E1035c6F6535B496B04Ab3a3` | ERC-20 token used for TucuWallet rewards and transfers. |
| TUCU implementation | `0x55Fe4A300FaDB38F774Ccfa596F95a5e39e70B60` | Current UUPS implementation behind the TUCU proxy. |
| RewardsDistributorV2 | `0x3f350C8Bc884189194186523D79a53D93095d846` | Mints fixed, signed and rate-limited TUCU rewards. |
| TucuTransferRouter | `0xB1d58EF2f8bfaA0aB6F0B881aC7d8c9bcB90296f` | Routes an exact approved token amount without retaining custody. |

External tokens supported by the router:

- WLD: `0x2cfc85d8e48f8eab294be644d9e25c3030863003`
- USDC: `0x79A02482A880bCE3F13e09Da970dC34db4CD24d1`

## Security model

### RewardsDistributorV2

- Does not hold user funds.
- Accepts only backend-signed EIP-712 authorizations.
- Enforces the configured mission amount on-chain.
- Enforces cooldown, lifetime and 30-day limits.
- Permanently rejects reused claim identifiers.
- Has a global limit of 100 TUCU per wallet in each 30-day window.
- Can be paused in an emergency.
- Cannot seize or withdraw tokens from users.

The public `daily_web3` mission awards 1 TUCU every 24 hours to an authenticated
World account with a valid wallet. Other protected missions can additionally
require World ID verification in the application backend.

### TucuTransferRouter

- Is non-custodial and has no withdrawal function.
- Pulls only the exact amount approved by the sender.
- Sends the recipient amount and separately accounted fee in one transaction.
- Ends each normal transfer without retaining user balances.
- Supports only explicitly allowlisted tokens.
- Has a permanent platform-fee cap of 1% (`100` basis points).
- Uses OpenZeppelin access control, pause protection and reentrancy protection.

## Administrative roles

- `DEFAULT_ADMIN_ROLE`: configures roles, allowed router tokens and treasury.
- `PAUSER_ROLE`: pauses or resumes affected contract operations.
- `MINTER_ROLE`: allows RewardsDistributorV2 to mint the configured TUCU amount.
- `REWARD_SIGNER_ROLE`: validates backend reward authorizations.
- `UPGRADER_ROLE`: authorizes TUCU implementation upgrades.

Production administrator:
`0xa2318a8C5A19bbed1176B6cA2a760A9C895f17c9`.

Production treasury:
`0xa8db5eda054fdd0d0fae3b5fbe34979d8c1fdd1f`.

Active reward signer:
`0x6e6Ccd023d6C572D322c8670E74ffA9253d39526`.

No private key is committed to this repository. Deployment and signer keys are
environment secrets and are never exposed to the frontend.

## Reproducibility and verification

- Solidity source is under `src/`.
- Machine-readable mainnet deployments are under `deployments/`.
- Mission configuration is under `config/`.
- Read-only verification scripts are under `scripts/`.
- Standard JSON compiler inputs used for WorldScan are under `worldscan/`.

Install dependencies with Node.js 22 or newer:

```text
npm ci
```

Compile:

```text
npm run compile
```

Audit the production rewards deployment:

```text
TUCU_REWARDS_DISTRIBUTOR_ADDRESS=0x3f350C8Bc884189194186523D79a53D93095d846
TUCU_ADMIN_ADDRESS=0xa2318a8C5A19bbed1176B6cA2a760A9C895f17c9
TUCU_REWARD_SIGNER_ADDRESS=0x6e6Ccd023d6C572D322c8670E74ffA9253d39526
npm run audit:rewards-v2
```

The audit checks the network, bytecode, token relationship, pause state, roles,
global reward limit and every configured mission.

## Mini App integration

TucuWallet calls the transfer router and rewards distributor through MiniKit's
`sendTransaction` command. TUCU, WLD and USDC, together with all direct contract
entrypoints, are declared in the TucuWallet Developer Portal draft.

Application: https://www.tucuwallet.com

