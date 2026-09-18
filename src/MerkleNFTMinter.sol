// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MerkleNFTMinter
 * @notice ERC-721 minter supporting allowlist (Merkle proof) and public sale phases,
 * exact payment enforcement, per-wallet limits, supply caps, pauseability, and owner withdrawals.
 */
contract MerkleNFTMinter is ERC721, Ownable, ReentrancyGuard, Pausable {
    using Strings for uint256;

    enum Phase {
        Inactive,
        Allowlist,
        Public
    }

    bytes32 public merkleRoot;
    uint256 public allowlistPrice;
    uint256 public publicPrice;
    uint256 public maxSupply;
    uint256 public publicPerWalletLimit;
    uint256 public totalMinted;
    Phase public currentPhase;
    string private _baseTokenURI;

    mapping(address => uint256) public allowlistMinted;
    mapping(address => uint256) public publicMinted;

    // Custom errors
    error PhaseInactive();
    error InvalidPhase();
    error InvalidPayment(uint256 expected, uint256 actual);
    error InvalidProof();
    error ExceedsAllowance(uint256 allowed, uint256 requested);
    error ExceedsMaxSupply(uint256 requested, uint256 remaining);
    error ZeroAmount();
    error ZeroAddress();
    error WithdrawFailed();
    error TokenDoesNotExist(uint256 tokenId);

    // Events
    event PhaseUpdated(Phase indexed oldPhase, Phase indexed newPhase);
    event MerkleRootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);
    event PricesUpdated(uint256 allowlistPrice, uint256 publicPrice);
    event Minted(address indexed minter, uint256 startTokenId, uint256 quantity, Phase indexed phase);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    event BaseURIUpdated(string newBaseURI);

    constructor(
        string memory name_,
        string memory symbol_,
        bytes32 merkleRoot_,
        uint256 allowlistPrice_,
        uint256 publicPrice_,
        uint256 maxSupply_,
        uint256 publicPerWalletLimit_,
        string memory baseURI_
    ) ERC721(name_, symbol_) Ownable(msg.sender) {
        merkleRoot = merkleRoot_;
        allowlistPrice = allowlistPrice_;
        publicPrice = publicPrice_;
        maxSupply = maxSupply_;
        publicPerWalletLimit = publicPerWalletLimit_;
        _baseTokenURI = baseURI_;
        currentPhase = Phase.Inactive;
    }

    /**
     * @notice Mint tokens during Allowlist phase using Merkle proof
     * @param quantity Number of tokens to mint
     * @param maxAllowance Total allowance assigned to caller in Merkle leaf
     * @param proof Merkle proof verifying (caller, maxAllowance)
     */
    function allowlistMint(
        uint256 quantity,
        uint256 maxAllowance,
        bytes32[] calldata proof
    ) external payable nonReentrant whenNotPaused {
        if (currentPhase != Phase.Allowlist) revert InvalidPhase();
        if (quantity == 0) revert ZeroAmount();

        uint256 expectedPayment = allowlistPrice * quantity;
        if (msg.value != expectedPayment) {
            revert InvalidPayment(expectedPayment, msg.value);
        }

        uint256 alreadyMinted = allowlistMinted[msg.sender];
        if (alreadyMinted + quantity > maxAllowance) {
            revert ExceedsAllowance(maxAllowance, alreadyMinted + quantity);
        }

        if (totalMinted + quantity > maxSupply) {
            revert ExceedsMaxSupply(quantity, maxSupply - totalMinted);
        }

        // Standard double keccak256 leaf to prevent second preimage attack
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, maxAllowance))));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
            revert InvalidProof();
        }

        allowlistMinted[msg.sender] = alreadyMinted + quantity;
        uint256 startTokenId = totalMinted + 1;
        totalMinted += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(msg.sender, startTokenId + i);
        }

        emit Minted(msg.sender, startTokenId, quantity, Phase.Allowlist);
    }

    /**
     * @notice Mint tokens during Public phase
     * @param quantity Number of tokens to mint
     */
    function publicMint(uint256 quantity) external payable nonReentrant whenNotPaused {
        if (currentPhase != Phase.Public) revert InvalidPhase();
        if (quantity == 0) revert ZeroAmount();

        uint256 expectedPayment = publicPrice * quantity;
        if (msg.value != expectedPayment) {
            revert InvalidPayment(expectedPayment, msg.value);
        }

        uint256 alreadyMinted = publicMinted[msg.sender];
        if (alreadyMinted + quantity > publicPerWalletLimit) {
            revert ExceedsAllowance(publicPerWalletLimit, alreadyMinted + quantity);
        }

        if (totalMinted + quantity > maxSupply) {
            revert ExceedsMaxSupply(quantity, maxSupply - totalMinted);
        }

        publicMinted[msg.sender] = alreadyMinted + quantity;
        uint256 startTokenId = totalMinted + 1;
        totalMinted += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(msg.sender, startTokenId + i);
        }

        emit Minted(msg.sender, startTokenId, quantity, Phase.Public);
    }

    /**
     * @notice Helper to generate the exact leaf format used by this contract
     */
    function getLeaf(address account, uint256 maxAllowance) external pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, maxAllowance))));
    }

    // --- Admin Functions ---

    function setPhase(Phase newPhase) external onlyOwner {
        Phase oldPhase = currentPhase;
        currentPhase = newPhase;
        emit PhaseUpdated(oldPhase, newPhase);
    }

    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = newRoot;
        emit MerkleRootUpdated(oldRoot, newRoot);
    }

    function setPrices(uint256 newAllowlistPrice, uint256 newPublicPrice) external onlyOwner {
        allowlistPrice = newAllowlistPrice;
        publicPrice = newPublicPrice;
        emit PricesUpdated(newAllowlistPrice, newPublicPrice);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert ZeroAmount();

        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert WithdrawFailed();

        emit FundsWithdrawn(owner(), balance);
    }

    // --- View Metadata ---

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);

        string memory base = _baseTokenURI;
        return bytes(base).length > 0 ? string(abi.encodePacked(base, tokenId.toString(), ".json")) : "";
    }
}
