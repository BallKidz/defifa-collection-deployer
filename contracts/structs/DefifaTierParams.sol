// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @member name The name of the tier.
/// @member price The price to mint from this tier.
/// @member reservedRate The number of minted tokens needed in the tier to allow for minting another reserved token.
/// @member reservedRateBeneficiary The beneificary of the reserved tokens for this tier.
/// @member encodedIPFSUri The URI to use for each token within the tier.
/// @member shouldUseReservedRateBeneficiaryAsDefault A flag indicating if the `reservedTokenBeneficiary` should be stored as the default beneficiary for all tiers, saving storage.
struct DefifaTierParams {
    string name;
    uint80 price;
    uint16 reservedRate;
    address reservedTokenBeneficiary;
    bytes32 encodedIPFSUri;
    bool shouldUseReservedTokenBeneficiaryAsDefault;
}
