# Merkle NFT Minter

An ERC-721 token minter contract supporting cryptographic Merkle proof allowlist verification and public minting phases, written in **Solidity ^0.8.20** and tested with **Foundry**.

## Core Features & Architecture

- **Cryptographic Allowlist (Merkle Trees):**
  - Leaf encoding: `keccak256(bytes.concat(keccak256(abi.encode(account, maxAllowance))))` (double-hashing standard to prevent second-preimage attacks).
  - OpenZeppelin `MerkleProof` verification.
- **Phase State Machine:**
  - Distinct sale phases (`Inactive`, `Allowlist`, `Public`).
  - Strict phase validation prevents early, late, or out-of-phase minting.
- **Custody & Economics:**
  - Exact-payment enforcement prevents underpayment and overpayment lockups.
  - Per-wallet mint tracking prevents allowance overclaiming.
  - Hard supply cap with exhaustion bounds.
- **Security & Administration:**
  - Non-reentrant public and allowlist mint functions (`ReentrancyGuard`).
  - Emergency circuit breaker (`Pausable`).
  - Pull-over-push owner withdrawal for ETH proceeds.

## Project Structure

```
├── foundry.toml
├── src/
│   └── MerkleNFTMinter.sol
├── script/
│   └── MerkleNFTMinter.s.sol
└── test/
    └── MerkleNFTMinter.t.sol
```

## Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/)

### Build
```bash
forge build
```

### Run Tests
```bash
forge test -vvv
```

All 12 test vectors pass, verifying valid/invalid Merkle proofs, proof tampering, duplicate claims, phase transitions, exact payments, supply exhaustion, and fuzz testing.
