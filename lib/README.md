# Vendored dependencies

These are ordinary source files, not submodules. No package download is needed to
build or test the project. `dependencies.json` records each upstream commit and
the SHA-256 hash of every vendored file.

- OpenZeppelin Contracts v5.0.2, commit
  `dbb6104ce834628e473d2173bbc9d47f81a9eec3`: the ERC20 implementation and its
  transitive source dependencies. Upstream:
  https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2
  License: `openzeppelin-contracts/LICENSE` (MIT).
- Forge Standard Library v1.9.7, commit
  `77041d2ce690e692d6e03cc812b57d1ddaa4d505`: the complete `src/` tree for tests.
  Upstream: https://github.com/foundry-rs/forge-std/tree/v1.9.7
  Licenses: `forge-std/LICENSE-APACHE` and `forge-std/LICENSE-MIT`.

Vendored files are unmodified. Only OpenZeppelin's ERC20 dependencies are included;
this is not a complete OpenZeppelin installation.
