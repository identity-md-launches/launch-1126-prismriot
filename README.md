# PrismRiot (PRIO)

PrismRiot is an immutable ERC-20. Its constructor mints all **1,000,000,000 PRIO**
to `msg.sender` once. There are **18 decimals**, so the exact supply in minor
units is **1000000000000000000000000000** (`10^27`).

## Design and assumptions

`src/PrismRiot.sol:PrismRiot` extends the vendored OpenZeppelin ERC20 implementation.
The requested token has standard transfers and approvals; no additional transfer
rules were specified. Transfers deliver exactly the requested amount. There are
no fees, burns, rebases, vesting, wallet limits, or external callbacks.

The constructor is the only minting path. There is no owner, minter, pause,
blacklist, seizure, upgrade, or initialization function. The deployer has the
initial balance but no special authority over other holders. Transferring to the
zero address reverts, including for a zero amount. Zero-value transfers between
nonzero accounts are allowed and emit `Transfer`.

`approve` replaces an allowance and emits `Approval`; setting it to zero revokes
it. `transferFrom` spends the caller's allowance, including when the caller is
the holder. The maximum `uint256` allowance is treated as unlimited and is not
decremented. Finite allowance consumption does not emit another `Approval` in
this implementation; query `allowance` for the current value. Invalid transfers
or approvals revert with ERC-6093 custom errors, and failed operations roll back
all balance and allowance changes.

## Build and test

Use Foundry with Solidity **0.8.26** available. All Solidity dependencies and
their licenses are ordinary files in `lib/`; nothing needs `forge install`,
submodules, npm, RPC access, environment variables, or network access once
Foundry and the pinned compiler are available.

```sh
forge build
forge test
forge fmt --check
```

The default profile pins the Cancun EVM target, optimizer with 200 runs, and
`bytecode_hash = "none"`. FFI and filesystem cheatcode permissions are not enabled.
Dependency commits and checksums are recorded in `lib/dependencies.json`.

Tests cover metadata, constructor mint events, direct and CREATE2 factory
deployment, exact forwarding and claim transfers, allowance spending/revocation,
unlimited approval behavior, zero and self transfers, insufficient funds and
allowances, invalid recipients, rollback on failure, absent administrative
entrypoints, native-currency rejection, and runtime opcode restrictions.
Four fuzz tests exercise transfer accounting and rejection boundaries. Stateful
invariants compare balances and allowances against an independent model across
sequences of transfers, approvals, and delegated transfers, and check total
supply conservation. The configured runs are 256 per fuzz test and 128 sequences
of up to 64 calls per invariant.

The local factory/pool-address test checks token accounting only. It does not
instantiate a Uniswap pool or replace the supplied external launch harness.
That harness needs platform contracts, a manifest, and platform-provided launch
values that are outside this token project. No pool economics or addresses are
assumed by the production contract.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Contract identifier | `src/PrismRiot.sol:PrismRiot` |
| Constructor arguments | None (`[]`, empty ABI encoding) |
| Native currency value | None; constructor is nonpayable |
| Token name / symbol | `PrismRiot` / `PRIO` |
| Decimals | `18` |
| Total supply, minor units | `1000000000000000000000000000` |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Required post-deployment calls | None |

Creation bytecode and ABI are produced at `out/PrismRiot.sol/PrismRiot.json`.
The creation bytecode can also be inspected locally with:

```sh
forge inspect src/PrismRiot.sol:PrismRiot bytecode
```

Deploy that creation bytecode with no appended arguments on a chain supporting
the pinned EVM target. An EOA deployment gives that EOA the entire supply. A
factory deployment gives the factory the entire supply; it must implement the
intended distribution. The constructor does not mint to `tx.origin` or an
independently configured recipient. The local factory test demonstrates CREATE2
deployment and forwarding. A launch manifest should reference the identifier,
empty constructor argument list, metadata, and exact supply above. Distribution,
pool creation, and launch economics remain responsibilities of the surrounding
launch system, not the token constructor.

This project does not broadcast transactions or require wallet keys. The
deployment operator selects the actual network, signer or factory, and any
CREATE2 salt outside this repository. No requester-specific address is needed
to compile or deploy the token.

## After launch

There are no token settings to configure and no administrative role to transfer.
The deployment operator should verify the deployed source and compiler settings,
metadata, exact supply, and initial recipient, then execute and verify any
authorized distribution through the launch system. Protect the wallet or
factory controlling the initial balance; token code cannot recover lost keys or
reverse mistaken transfers.

Holders manage their own allowances. Use bounded approvals when possible;
revoke an existing allowance before replacing it to reduce the standard ERC-20
approval-change race. Unlimited approval permits a spender to use current and
future balances until revoked. The token contract has no asset recovery method;
tokens transferred to its own address cannot be recovered. Ordinary native
currency transfers revert, and forcibly sent native currency cannot be recovered.

## Review and validation scope

The security review focused on constructor supply, allowance authorization,
conservation, invalid-address handling, and the absence of privileged mutation
or external calls. Reentrancy hooks, oracle reads, signatures, and proxy storage
are absent. The production change is the fixed metadata and a single constructor
mint on top of the vendored ERC20 implementation.

Foundry unit, fuzz, and invariant tests are the local validation tools. Slither
and Mythril are not part of the reported checks. Local tests are not an
independent audit; a separate adversarial review and the platform's full launch
integration checks remain release responsibilities.

Local validation completed with Foundry 1.8.5 and Solidity 0.8.26:

- `forge build`: passed.
- `forge test`: 28 tests passed, none failed or skipped. This Foundry version
  groups the two invariant properties into one test result; they ran across
  8,192 handler calls with zero reverts, alongside 27 unit/fuzz tests.
- `forge fmt --check`: passed.
- All 36 vendored files matched their recorded SHA-256 checksums. The compiled
  artifact confirmed empty constructor arguments, no metadata hash, and a
  deployed runtime of 1,752 bytes.
