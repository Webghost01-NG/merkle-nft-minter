// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MerkleNFTMinter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract MerkleNFTMinterTest is Test {
    MerkleNFTMinter public minter;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public david = makeAddr("david");
    address public eve = makeAddr("eve");

    uint256 public constant AL_PRICE = 0.05 ether;
    uint256 public constant PUB_PRICE = 0.08 ether;
    uint256 public constant MAX_SUPPLY = 10;
    uint256 public constant PUB_LIMIT = 2;

    bytes32 public root;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        vm.deal(david, 10 ether);
        vm.deal(eve, 10 ether);

        // Leaves:
        // alice: allowance 2
        // bob: allowance 3
        // carol: allowance 1
        // david: allowance 5
        bytes32 leaf0 = keccak256(bytes.concat(keccak256(abi.encode(alice, uint256(2)))));
        bytes32 leaf1 = keccak256(bytes.concat(keccak256(abi.encode(bob, uint256(3)))));
        bytes32 leaf2 = keccak256(bytes.concat(keccak256(abi.encode(carol, uint256(1)))));
        bytes32 leaf3 = keccak256(bytes.concat(keccak256(abi.encode(david, uint256(5)))));

        bytes32 node01 = _hashPair(leaf0, leaf1);
        bytes32 node23 = _hashPair(leaf2, leaf3);
        root = _hashPair(node01, node23);

        // Alice proof: [leaf1, node23]
        aliceProof = new bytes32[](2);
        aliceProof[0] = leaf1;
        aliceProof[1] = node23;

        // Bob proof: [leaf0, node23]
        bobProof = new bytes32[](2);
        bobProof[0] = leaf0;
        bobProof[1] = node23;

        vm.prank(owner);
        minter = new MerkleNFTMinter(
            "Test NFT",
            "TNFT",
            root,
            AL_PRICE,
            PUB_PRICE,
            MAX_SUPPLY,
            PUB_LIMIT,
            "https://meta.example.com/"
        );
    }

    function test_InitialState() public view {
        assertEq(uint256(minter.currentPhase()), uint256(MerkleNFTMinter.Phase.Inactive));
        assertEq(minter.merkleRoot(), root);
        assertEq(minter.allowlistPrice(), AL_PRICE);
        assertEq(minter.publicPrice(), PUB_PRICE);
        assertEq(minter.maxSupply(), MAX_SUPPLY);
        assertEq(minter.publicPerWalletLimit(), PUB_LIMIT);
        assertEq(minter.totalMinted(), 0);
    }

    function test_PhaseTransitionAndInactiveMintReverts() public {
        vm.prank(alice);
        vm.expectRevert(MerkleNFTMinter.InvalidPhase.selector);
        minter.allowlistMint{value: AL_PRICE}(1, 2, aliceProof);

        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Allowlist);
        assertEq(uint256(minter.currentPhase()), uint256(MerkleNFTMinter.Phase.Allowlist));

        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Public);
        assertEq(uint256(minter.currentPhase()), uint256(MerkleNFTMinter.Phase.Public));
    }

    function test_AllowlistMint_Success() public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Allowlist);

        vm.prank(alice);
        minter.allowlistMint{value: AL_PRICE * 2}(2, 2, aliceProof);

        assertEq(minter.balanceOf(alice), 2);
        assertEq(minter.allowlistMinted(alice), 2);
        assertEq(minter.totalMinted(), 2);
        assertEq(minter.ownerOf(1), alice);
        assertEq(minter.ownerOf(2), alice);
        assertEq(minter.tokenURI(1), "https://meta.example.com/1.json");
    }

    function test_AllowlistMint_PartialAndRepeatClaims() public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Allowlist);

        // Bob mints 1
        vm.prank(bob);
        minter.allowlistMint{value: AL_PRICE}(1, 3, bobProof);
        assertEq(minter.allowlistMinted(bob), 1);

        // Bob mints 2 more
        vm.prank(bob);
        minter.allowlistMint{value: AL_PRICE * 2}(2, 3, bobProof);
        assertEq(minter.allowlistMinted(bob), 3);

        // Bob attempts to mint 1 more (exceeds allowance)
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(MerkleNFTMinter.ExceedsAllowance.selector, 3, 4));
        minter.allowlistMint{value: AL_PRICE}(1, 3, bobProof);
    }

    function test_AllowlistMint_InvalidProofOrAlteredAllowance() public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Allowlist);

        // Eve tries to use Alice's proof
        vm.prank(eve);
        vm.expectRevert(MerkleNFTMinter.InvalidProof.selector);
        minter.allowlistMint{value: AL_PRICE}(1, 2, aliceProof);

        // Alice tries to lie about allowance (claiming allowance is 5)
        vm.prank(alice);
        vm.expectRevert(MerkleNFTMinter.InvalidProof.selector);
        minter.allowlistMint{value: AL_PRICE}(1, 5, aliceProof);
    }

    function test_AllowlistMint_PaymentChecks() public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Allowlist);

        // Underpay
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MerkleNFTMinter.InvalidPayment.selector, AL_PRICE, AL_PRICE - 1));
        minter.allowlistMint{value: AL_PRICE - 1}(1, 2, aliceProof);

        // Overpay
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MerkleNFTMinter.InvalidPayment.selector, AL_PRICE, AL_PRICE + 0.01 ether));
        minter.allowlistMint{value: AL_PRICE + 0.01 ether}(1, 2, aliceProof);
    }

    function test_PublicMint_SuccessAndLimit() public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Public);

        vm.prank(eve);
        minter.publicMint{value: PUB_PRICE * 2}(2);
        assertEq(minter.balanceOf(eve), 2);
        assertEq(minter.publicMinted(eve), 2);

        // Exceeding per-wallet limit
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(MerkleNFTMinter.ExceedsAllowance.selector, PUB_LIMIT, 3));
        minter.publicMint{value: PUB_PRICE}(1);
    }

    function test_SupplyExhaustion() public {
        // Deploy a small minter with max supply = 2
        vm.prank(owner);
        MerkleNFTMinter smallMinter = new MerkleNFTMinter(
            "Small", "SM", root, AL_PRICE, PUB_PRICE, 2, 5, ""
        );

        vm.prank(owner);
        smallMinter.setPhase(MerkleNFTMinter.Phase.Public);

        vm.prank(alice);
        smallMinter.publicMint{value: PUB_PRICE * 2}(2);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(MerkleNFTMinter.ExceedsMaxSupply.selector, 1, 0));
        smallMinter.publicMint{value: PUB_PRICE}(1);
    }

    function test_PausePreventsMinting() public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Public);

        vm.prank(owner);
        minter.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        minter.publicMint{value: PUB_PRICE}(1);

        vm.prank(owner);
        minter.unpause();

        vm.prank(alice);
        minter.publicMint{value: PUB_PRICE}(1);
        assertEq(minter.balanceOf(alice), 1);
    }

    function test_WithdrawFunds() public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Public);

        vm.prank(alice);
        minter.publicMint{value: PUB_PRICE}(1);

        uint256 ownerBalBefore = owner.balance;
        vm.prank(owner);
        minter.withdraw();
        assertEq(owner.balance, ownerBalBefore + PUB_PRICE);
        assertEq(address(minter).balance, 0);

        // Withdraw again with zero balance
        vm.prank(owner);
        vm.expectRevert(MerkleNFTMinter.ZeroAmount.selector);
        minter.withdraw();
    }

    function test_UnauthorizedControlsRevert() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        minter.setPhase(MerkleNFTMinter.Phase.Public);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        minter.withdraw();
    }

    function testFuzz_AllowlistMint(uint8 quantity) public {
        vm.prank(owner);
        minter.setPhase(MerkleNFTMinter.Phase.Allowlist);

        // Allowance for Alice is 2
        vm.assume(quantity > 0 && quantity <= 2);

        vm.prank(alice);
        minter.allowlistMint{value: AL_PRICE * quantity}(quantity, 2, aliceProof);
        assertEq(minter.balanceOf(alice), quantity);
    }
}
