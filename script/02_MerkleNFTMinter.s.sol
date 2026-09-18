// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MerkleNFTMinter.sol";

contract DeployMerkleNFTMinter is Script {
    function run() external returns (MerkleNFTMinter minter) {
        vm.startBroadcast();

        bytes32 sampleRoot = bytes32(0);
        uint256 allowlistPrice = 0.05 ether;
        uint256 publicPrice = 0.08 ether;
        uint256 maxSupply = 1000;
        uint256 publicLimit = 5;
        string memory baseURI = "https://api.example.com/nft/";

        minter = new MerkleNFTMinter(
            "Foundry Genesis",
            "FGEN",
            sampleRoot,
            allowlistPrice,
            publicPrice,
            maxSupply,
            publicLimit,
            baseURI
        );

        vm.stopBroadcast();
    }
}
