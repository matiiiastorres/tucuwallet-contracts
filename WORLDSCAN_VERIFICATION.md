# WorldScan verification

Checked on 2026-08-13 against World Chain mainnet (chain ID 480).

| Contract | Address | Solidity | Optimizer | WorldScan |
| --- | --- | --- | --- | --- |
| TucuProxy | `0x2dCFE82458e2dc32E1035c6F6535B496B04Ab3a3` | 0.8.24 | 200 runs | Verified |
| TucuToken implementation | `0x55Fe4A300FaDB38F774Ccfa596F95a5e39e70B60` | 0.8.24 | 200 runs | Verified |
| RewardsDistributorV2 | `0x3f350C8Bc884189194186523D79a53D93095d846` | 0.8.36 | 200 runs | Verified |
| TucuTransferRouter | `0xB1d58EF2f8bfaA0aB6F0B881aC7d8c9bcB90296f` | 0.8.24 | 200 runs | Verified |

The proxy page links to the expected TucuToken implementation. The production
source files in `src/` are exact text matches for their corresponding source
entries in the standard JSON compiler inputs stored under `worldscan/`.

Direct explorer links:

- https://worldscan.org/address/0x2dCFE82458e2dc32E1035c6F6535B496B04Ab3a3#code
- https://worldscan.org/address/0x55Fe4A300FaDB38F774Ccfa596F95a5e39e70B60#code
- https://worldscan.org/address/0x3f350C8Bc884189194186523D79a53D93095d846#code
- https://worldscan.org/address/0xB1d58EF2f8bfaA0aB6F0B881aC7d8c9bcB90296f#code
