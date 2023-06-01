// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import "@jbx-protocol/juice-721-delegate/contracts/libraries/JBIpfsDecoder.sol";
import "lib/base64/base64.sol";
import "./interfaces/IDefifaDelegate.sol";
import "./interfaces/IDefifaTokenUriResolver.sol";
import "./libraries/DefifaFontImporter.sol";
import "./libraries/DefifaPercentFormatter.sol";

/**
 * @title
 *   DefifaDelegate
 * 
 *   @notice
 *   Defifa default 721 token URI resolver.
 * 
 *   @dev
 *   Adheres to -
 *   IDefifaTokenUriResolver: General interface for the methods in this contract that interact with the blockchain's state according to the protocol's rules.
 *   IJBTokenUriResolver: Interface to ensure compatibility with 721Delegates.
 */
contract DefifaTokenUriResolver is IDefifaTokenUriResolver, IJBTokenUriResolver {
    using Strings for uint256;

    //*********************************************************************//
    // -------------------- private constant properties ------------------ //
    //*********************************************************************//

    /**
     * @notice
     * The fidelity of the decimal returned in the NFT image.
     */
    uint256 private constant _IMG_DECIMAL_FIDELITY = 5;

    //*********************************************************************//
    // --------------------- private stored properties ------------------- //
    //*********************************************************************//

    /**
     * @notice
     * The names of each tier.
     * 
     * @dev _tierId The ID of the tier to get a name for.
     */
    mapping(uint256 => string) private _tierNameOf;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /**
     * @notice
     * The address of the origin 'DefifaGovernor', used to check in the init if the contract is the original or not
     */
    address public immutable override codeOrigin;

    /**
     * @notice
     * The typeface of the SVGs.
     */
    ITypeface public immutable override typeface;

    //*********************************************************************//
    // -------------------- public stored properties --------------------- //
    //*********************************************************************//

    /**
     * @notice
     * The delegate being shown.
     */
    IDefifaDelegate public override delegate;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /**
     * @notice
     * The name of the tier with the specified ID.
     * 
     * @param _tierId The ID of the tier to get the name of.
     * 
     * @return The tier's name.
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
     * @notice
     * Initializes the contract.
     * 
     * @param _delegate The Defifa delegate contract that this contract is showing.
     * @param _tierNames The names of each tier.
     */
    function initialize(IDefifaDelegate _delegate, string[] memory _tierNames) public virtual override {
        // Make the original un-initializable.
        if (address(this) == codeOrigin) revert();

        // Stop re-initialization.
        if (address(delegate) != address(0)) revert();

        delegate = _delegate;

        // Keep a reference to the number of tier names.
        uint256 _numberOfTierNames = _tierNames.length;

        // Set the name for each tier.
        for (uint256 _i; _i < _numberOfTierNames;) {
            // Set the tier name.
            _tierNameOf[_i + 1] = _tierNames[_i];

            unchecked {
                ++_i;
            }
        }
    }

    /**
     * @notice
     * The metadata URI of the provided token ID.
     * 
     * @dev
     * Defer to the token's tier IPFS URI if set.
     * 
     * @param _tokenId The ID of the token to get the tier URI for.
     * 
     * @return The token URI corresponding with the tier.
     */
    function getUri(uint256 _tokenId) external view override returns (string memory) {
        // Keep a reference to the delegate.
        IDefifaDelegate _delegate = delegate;

        // Get the game ID.
        uint256 _gameId = _delegate.projectId();

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
            if (_tier.encodedIPFSUri != bytes32(0)) {
                return JBIpfsDecoder.decode(_delegate.baseURI(), _tier.encodedIPFSUri);
            }

            parts[0] = string("data:application/json;base64,");

            parts[1] = string(
                abi.encodePacked(
                    '{"name":"',
                    _team,
                    '", "id": "',
                    _tier.id.toString(),
                    '","description":"Team: ',
                    _team,
                    ", ID: ",
                    _tier.id.toString(),
                    '.","image":"data:image/svg+xml;base64,'
                )
            );

            {
                // Get a reference to the game phase.
                DefifaGamePhase _gamePhase = delegate.gamePhaseReporter().currentGamePhaseOf(_gameId);

                if (_gamePhase == DefifaGamePhase.NO_CONTEST) {
                    _gamePhaseText = "No contest. Refunds open.";
                } else if (_gamePhase == DefifaGamePhase.NO_CONTEST_INEVITABLE) {
                    _gamePhaseText = "No contest inevitable. Refunds open.";
                } else if (_gamePhase == DefifaGamePhase.COUNTDOWN) {
                    _gamePhaseText = "Minting starts soon.";
                } else if (_gamePhase == DefifaGamePhase.MINT) {
                    _gamePhaseText = "Minting and refunds are open. Game starts soon.";
                } else if (_gamePhase == DefifaGamePhase.REFUND) {
                    _gamePhaseText = "Game starting, minting closed. Last chance for refunds.";
                } else if (_gamePhase == DefifaGamePhase.SCORING && !_delegate.redemptionWeightIsSet()) {
                    _gamePhaseText = "Awaiting approved scorecard.";
                } else {
                    string memory _percentOfPot = DefifaPercentFormatter.getFormattedPercentageOfRedemptionWeight(
                        _delegate.redemptionWeightOf(_tokenId),
                        _delegate.TOTAL_REDEMPTION_WEIGHT(),
                        _IMG_DECIMAL_FIDELITY
                    );
                    _gamePhaseText =
                        string(abi.encodePacked("Scorecard approved. Redeem for ~", _percentOfPot, " of pot."));
                }

                uint256 _totalMinted = _tier.initialQuantity - _tier.remainingQuantity;
                if (_gamePhase == DefifaGamePhase.MINT) {
                    _rarityText = string(abi.encodePacked(_totalMinted.toString(), " minted so far"));
                } else {
                    _rarityText = string(abi.encodePacked(_totalMinted.toString(), " in existence"));
                }
            }
        }
        parts[2] = Base64.encode(
            abi.encodePacked(
                '<svg viewBox="0 0 500 500" xmlns="http://www.w3.org/2000/svg">',
                '<style>@font-face{font-family:"Capsules-500";src:url(data:font/truetype;charset=utf-8;base64,',
                DefifaFontImporter.getSkinnyFontSource(typeface),
                ');format("opentype");}',
                '@font-face{font-family:"Capsules-700";src:url(data:font/truetype;charset=utf-8;base64,',
                DefifaFontImporter.getBeefyFontSource(typeface),
                ');format("opentype");}',
                "text{white-space:pre-wrap; width:100%; }</style>",
                '<rect width="100%" height="100%" fill="#181424"/>',
                '<text x="10" y="30" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">GAME ID: ',
                _gameId.toString(),
                "</text>",
                '<text x="10" y="50" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #ed017c;">',
                _gamePhaseText,
                "</text>",
                '<text x="10" y="80" style="font-size:26px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">',
                _getSubstring(_title, 0, 29),
                "</text>",
                '<text x="10" y="115" style="font-size:26px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">',
                _getSubstring(_title, 30, 59),
                "</text>",
                '<text x="10" y="150" style="font-size:26px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">',
                _getSubstring(_title, 60, 89),
                "</text>",
                '<text x="10" y="230" style="font-size:80px; font-family: Capsules-700; font-weight:700; fill: #fea282;">',
                bytes(_getSubstring(_team, 20, 29)).length != 0 && bytes(_getSubstring(_team, 10, 19)).length != 0 ? _getSubstring(_team, 0, 9) : "",
                "</text>",
                '<text x="10" y="320" style="font-size:80px; font-family: Capsules-700; font-weight:700; fill: #fea282;">',
                bytes(_getSubstring(_team, 20, 29)).length != 0 ? _getSubstring(_team, 10, 19) : bytes(_getSubstring(_team, 10, 19)).length != 0 ? _getSubstring(_team, 0, 9) : "",
                "</text>",
                '<text x="10" y="410" style="font-size:80px; font-family: Capsules-700; font-weight:700; fill: #fea282;">',
                bytes(_getSubstring(_team, 20, 29)).length != 0 ? _getSubstring(_team, 20, 29) : bytes(_getSubstring(_team, 10, 19)).length != 0 ? _getSubstring(_team, 10, 19) : _getSubstring(_team, 0, 9),
                "</text>",
                '<text x="10" y="455" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">TOKEN ID: ',
                _tokenId.toString(),
                "</text>",
                '<text x="10" y="480" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">RARITY: ',
                _rarityText,
                "</text>",
                "</svg>"
            )
        );
        parts[3] = string('"}');
        return string.concat(parts[0], Base64.encode(abi.encodePacked(parts[1], parts[2], parts[3])));
    }

    function _getSubstring(string memory _str, uint256 _startIndex, uint256 _endIndex) internal pure returns (string memory substring) {
        bytes memory _strBytes = bytes(_str);
        if(_startIndex >= _strBytes.length) return "";
        if(_endIndex > _strBytes.length) _endIndex = _strBytes.length;
        if(_startIndex >= _endIndex) return "";
        bytes memory _result = new bytes(_endIndex-_startIndex);
        for(uint256 _i = _startIndex; _i < _endIndex;) {
            _result[_i-_startIndex] = _strBytes[_i];
            unchecked {
              ++_i;
            }
        }
        return _removeLeadingSpace(_result);
    }

    function _removeLeadingSpace(bytes memory _strBytes) internal pure returns (string memory) {
        if (_strBytes.length == 0 || _strBytes[0] != bytes1(0x20)) {
            return string(_strBytes);
        }
        bytes memory _result = new bytes(_strBytes.length - 1);
        for (uint _i = 1; _i < _strBytes.length;) {
            _result[_i - 1] = _strBytes[_i];
            unchecked {
              ++_i;
            }
        }
        return string(_result);
    }
}
