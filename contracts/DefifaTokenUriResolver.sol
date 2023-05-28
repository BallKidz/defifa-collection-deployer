// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/utils/Strings.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol';
import '@jbx-protocol/juice-721-delegate/contracts/libraries/JBIpfsDecoder.sol';
import 'lib/base64/base64.sol';
import './interfaces/IDefifaDelegate.sol';
import './interfaces/IDefifaTokenUriResolver.sol';
import './libraries/DefifaFontImporter.sol';
import './libraries/DefifaPercentFormatter.sol';

/** 
  @title
  DefifaDelegate

  @notice
  Defifa default 721 token URI resolver.

  @dev
  Adheres to -
  IDefifaTokenUriResolver: General interface for the methods in this contract that interact with the blockchain's state according to the protocol's rules.
  IJBTokenUriResolver: Interface to ensure compatibility with 721Delegates.
*/
contract DefifaTokenUriResolver is IDefifaTokenUriResolver, IJBTokenUriResolver {
  using Strings for uint256;

  //*********************************************************************//
  // -------------------- private constant properties ------------------ //
  //*********************************************************************//

  /**
    @notice
    The fidelity of the decimal returned in the NFT image.
  */
  uint256 private constant _IMG_DECIMAL_FIDELITY = 5;

  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  /**
    @notice
    The names of each tier.

    @dev _tierId The ID of the tier to get a name for.
  */
  mapping(uint256 => string) private _tierNameOf;

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /**
    @notice
    The address of the origin 'DefifaGovernor', used to check in the init if the contract is the original or not
  */
  address public immutable override codeOrigin;

  /**
    @notice
    The typeface of the SVGs.
  */
  ITypeface public override immutable typeface;

  //*********************************************************************//
  // -------------------- public stored properties --------------------- //
  //*********************************************************************//

  /**
    @notice
    The delegate being shown.
  */
  IDefifaDelegate public override delegate;

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /** 
    @notice
    The name of the tier with the specified ID.

    @param _tierId The ID of the tier to get the name of.

    @return The tier's name.
  */
  function tierNameOf(uint256 _tierId) external view override returns (string memory) {
    return _tierNameOf[_tierId];
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor(ITypeface _typeface) {
    codeOrigin = address(this);
    typeface = _typeface;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /**     
    @notice
    Initializes the contract.

    @param _delegate The Defifa delegate contract that this contract is showing.
    @param _tierNames The names of each tier.
  */
  function initialize(
    IDefifaDelegate _delegate,
    string[] memory _tierNames
  ) public virtual override {
    // Make the original un-initializable.
    if (address(this) == codeOrigin) revert();

    // Stop re-initialization.
    if (address(delegate) != address(0)) revert();

    delegate = _delegate;

    // Keep a reference to the number of tier names.
    uint256 _numberOfTierNames = _tierNames.length;

    // Set the name for each tier.
    for (uint256 _i; _i < _numberOfTierNames; ) {
      // Set the tier name.
      _tierNameOf[_i + 1] = _tierNames[_i];

      unchecked {
        ++_i;
      }
    }
  }

  /**
    @notice
    The metadata URI of the provided token ID.

    @dev
    Defer to the token's tier IPFS URI if set.

    @param _tokenId The ID of the token to get the tier URI for.

    @return The token URI corresponding with the tier.
  */
  function getUri(uint256 _tokenId) external view override returns (string memory) {
    // Keep a reference to the delegate.
    IDefifaDelegate _delegate = delegate;

    // Get the game ID.
    uint256 _gameId = _delegate.projectId();

    // Keep a reference to the font size.
    string memory _fontSize;

    // Keep a reference to the game phase text.
    string memory _gamePhaseText;

    // Keep a reference to the rarity text;
    string memory _rarityText;

    // Keep a reference to the game's name.
    string memory _title = _delegate.name();

    // Keep a reference to the tier's name.
    string memory _team;

    // Keep a reference to the SVG parts.
    string[] memory parts = new string[](4);

    {
      // Get a reference to the tier.
      JB721Tier memory _tier = _delegate.store().tierOfTokenId(address(_delegate), _tokenId, false);

      // Set the tier's name.
      _team = _tierNameOf[_tier.id];

      // Check to see if the tier has a URI. Return it if it does.
      if (_tier.encodedIPFSUri != bytes32(0))
        return JBIpfsDecoder.decode(_delegate.baseURI(), _tier.encodedIPFSUri);

      parts[0] = string('data:application/json;base64,');

      parts[1] = string(
        abi.encodePacked(
          '{"name":"',
          _title,
          '", "id": "',
          _tier.id.toString(),
          '","description":"Team: ',
          _team,
          ', ID: ',
          _tier.id.toString(),
          '.","image":"data:image/svg+xml;base64,'
        )
      );

      if (bytes(_team).length < 3) _fontSize = '240';
      else if (bytes(_team).length < 5) _fontSize = '200';
      else if (bytes(_team).length < 8) _fontSize = '120';
      else if (bytes(_team).length < 10) _fontSize = '90';
      else if (bytes(_team).length < 12) _fontSize = '85';
      else if (bytes(_team).length < 16) _fontSize = '80';
      else if (bytes(_team).length < 23) _fontSize = '70';
      else if (bytes(_team).length < 30) _fontSize = '50';
      else if (bytes(_team).length < 35) _fontSize = '40';
      else _fontSize = '16';

      {
        // Get a reference to the game phase.
        DefifaGamePhase _gamePhase = delegate.gamePhaseReporter().currentGamePhaseOf(_gameId);

        if (_gamePhase == DefifaGamePhase.NO_CONTEST) _gamePhaseText = 'No contest. Refunds open.';
        else if (_gamePhase == DefifaGamePhase.NO_CONTEST_INEVITABLE) _gamePhaseText = 'No contest inevitable. Refunds open.';
        else if (_gamePhase == DefifaGamePhase.COUNTDOWN) _gamePhaseText = 'Minting starts soon.';
        else if (_gamePhase == DefifaGamePhase.MINT) _gamePhaseText = 'Minting and refunds are open. Game starts soon.';
        else if (_gamePhase == DefifaGamePhase.REFUND)
          _gamePhaseText = 'Game starting, minting closed. Last chance for refunds.';
        else if (_gamePhase == DefifaGamePhase.SCORING && !_delegate.redemptionWeightIsSet())
          _gamePhaseText = 'Awaiting approved scorecard.';
        else {
          string memory _percentOfPot = DefifaPercentFormatter.getFormattedPercentageOfRedemptionWeight(
            _delegate.redemptionWeightOf(_tokenId),
            _delegate.TOTAL_REDEMPTION_WEIGHT(),
            _IMG_DECIMAL_FIDELITY
          );
          _gamePhaseText = string(
            abi.encodePacked('Scorecard approved. Redeem for ~', _percentOfPot, ' of pot.')
          );
        }

        uint256 _totalMinted = _tier.initialQuantity - _tier.remainingQuantity;
        if (_gamePhase == DefifaGamePhase.MINT)
          _rarityText = string(abi.encodePacked(_totalMinted.toString(), ' minted so far'));
        else _rarityText = string(abi.encodePacked(_totalMinted.toString(), ' in existence'));
      }
    }


    parts[2] = Base64.encode(
      abi.encodePacked(
        '<svg width="500" height="500" viewBox="0 0 100% 100%" xmlns="http://www.w3.org/2000/svg">',
        '<style>@font-face{font-family:"Capsules-300";src:url(data:font/truetype;charset=utf-8;base64,',
        DefifaFontImporter.getSkinnyFontSource(typeface),
        ');format("opentype");}',
        '@font-face{font-family:"Capsules-700";src:url(data:font/truetype;charset=utf-8;base64,',
        DefifaFontImporter.getBeefyFontSource(typeface),
        ');format("opentype");}',
        'text{white-space:pre-wrap; width:100%; }</style>',
        '<rect width="100%" height="100%" fill="#181424"/>',
        '<text x="10" y="40" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #c0b3f1;">GAME ID: ',
         _gameId.toString(),
        '</text>',
        '<text x="10" y="60" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #ed017c;">',
        _gamePhaseText,
        '</text>',
        '<foreignObject width="90%" height="80px" x="10" y="70" ><div xmlns="http://www.w3.org/1999/xhtml" style="font-size:22px; font-family: Capsules-300; font-weight:300; color:#fea282;"><span style="word-wrap: break-word; white-space: pre-line;">',
        _title,
        '</span></div></foreignObject>',
        '<text x="10" y="455" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #c0b3f1;">TOKEN ID: ',
        _tokenId.toString(),
        '</text>',
        '<text x="10" y="480" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #c0b3f1;">RARITY: ',
        _rarityText,
        '</text>',
        '<foreignObject width="calc(100% - 20px)" height="50%" x="10" y="25%" ><div xmlns="http://www.w3.org/1999/xhtml" style="font-size:',
        _fontSize,
        'px; font-family: Capsules-700; font-weight:700; color:#fea282; display: flex; align-items: center; height: 100%; text-align: left; letter-spacing: 1px;"><span style="word-wrap: break-word; white-space: pre-line;">',
        _team,
        '</span></div></foreignObject>',
        '</svg>'
      )
    );
    parts[3] = string('"}');
    return string.concat(parts[0], Base64.encode(abi.encodePacked(parts[1], parts[2], parts[3])));
  }
}
