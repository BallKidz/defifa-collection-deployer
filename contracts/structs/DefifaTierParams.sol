// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
  @member price The cost to mint from this tier.
  @memver reservedRate The number of minted tokens needed in the tier to allow for minting another reserved token.
  @member reservedRateBeneficiary The beneificary of the reserved tokens for this tier.
  @member royaltyRate The percentage of each of the NFT sales that should be routed to the royalty beneficiary. Out of MAX_ROYALTY_RATE.
  @member royaltyBeneficiary The beneificary of the royalty.
  @member encodedIPFSUri The URI to use for each token within the tier.
  @member shouldUseReservedRateBeneficiaryAsDefault A flag indicating if the `reservedTokenBeneficiary` should be stored as the default beneficiary for all tiers.
  @member name The name of the tier.
*/
struct DefifaTierParams {
  uint80 price;
  uint16 reservedRate;
  address reservedTokenBeneficiary;
  uint8 royaltyRate;
  address royaltyBeneficiary;
  bytes32 encodedIPFSUri;
  bool shouldUseReservedTokenBeneficiaryAsDefault;
  string name;
}
