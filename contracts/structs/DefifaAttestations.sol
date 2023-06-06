// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct DefifaAttestations {
    uint256 count;
    mapping(address => bool) hasAttested;
}
