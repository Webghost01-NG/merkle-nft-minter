# Merkle NFT Minter

> **What it is about:** A gas-efficient ERC-721 NFT minting smart contract that uses cryptographic Merkle trees for off-chain allowlist validation instead of costly on-chain storage.
>
> **What it does:** Allows eligible allowlist users to mint NFTs at a discounted price by submitting a cryptographic proof verifying their address and assigned quota, transitions into an open public sale phase with per-wallet caps, enforces exact ETH payments, and provides emergency pause switches and secure owner fund withdrawals.

---

## Key Features & Architecture

- **Cryptographic Allowlist (Merkle Trees):**
  - Leaf encoding: `keccak256(bytes.concat(keccak256(abi.encode(account, maxAllowance))))` (double-hashing standard to prevent second-preimage attacks).
  - OpenZeppelin `MerkleProof` verification.
- **Phase State Machine:**
  - Distinct sale phases: `Inactive` -> `Allowlist` -> `Public`.
  - Strict validation rejects early, late, or cross-phase minting attempts.
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
