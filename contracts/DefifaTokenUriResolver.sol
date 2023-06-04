// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@paulrberg/contracts/math/PRBMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-721-delegate/contracts/libraries/JBIpfsDecoder.sol";
import "lib/base64/base64.sol";
import "./interfaces/IDefifaDelegate.sol";
import "./interfaces/IDefifaTokenUriResolver.sol";
import "./libraries/DefifaFontImporter.sol";

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
    using SafeMath for uint256;

    //*********************************************************************//
    // -------------------- private constant properties ------------------ //
    //*********************************************************************//

    /**
     * @notice
     * The fidelity of the decimal returned in the NFT image.
     */
    uint256 private constant _IMG_DECIMAL_FIDELITY = 3;

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

        // Keep a reference to the rarity text;
        string memory _valueText;

        // Keep a reference to the game's name.
        string memory _title = _delegate.name();

        // Keep a reference to the tier's name.
        string memory _team;

        // Keep a reference to the SVG parts.
        string[] memory parts = new string[](4);

        // Keep a reference to the pot.
        string memory _potText;

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

                // Keep a reference to the game pot.
                (uint256 _gamePot, address _gamePotToken, uint256 _gamePotDecimals) =
                    _delegate.gamePotReporter().currentGamePotOf(_gameId);

                // Include the amount redeemed.
                _gamePot = _gamePot + delegate.amountRedeemed();

                // Set the pot text.
                _potText = _formatBalance(_gamePot, _gamePotToken, _gamePotDecimals, _IMG_DECIMAL_FIDELITY);

                if (_gamePhase == DefifaGamePhase.NO_CONTEST) {
                    _gamePhaseText = "No contest. Refunds open.";
                } else if (_gamePhase == DefifaGamePhase.NO_CONTEST_INEVITABLE) {
                    _gamePhaseText = "No contest inevitable. Refunds open.";
                } else if (_gamePhase == DefifaGamePhase.COUNTDOWN) {
                    _gamePhaseText = "Minting starts soon.";
                } else if (_gamePhase == DefifaGamePhase.MINT) {
                    _gamePhaseText = "Minting and refunds are open.";
                } else if (_gamePhase == DefifaGamePhase.REFUND) {
                    _gamePhaseText = "Minting is over. Refunds are ending.";
                } else if (_gamePhase == DefifaGamePhase.SCORING) {
                    _gamePhaseText = "Awaiting scorecard approval.";
                } else if (_gamePhase == DefifaGamePhase.COMPLETE) {
                    _gamePhaseText = "Scorecard approved. Burn to claim reward.";
                }

                // Keep a reference to the number of tokens outstanding from this tier.
                uint256 _totalMinted = _tier.initialQuantity - _tier.remainingQuantity;

                if (_gamePhase == DefifaGamePhase.MINT) {
                    _rarityText = string(abi.encodePacked(_totalMinted.toString(), " minted so far"));
                } else {
                    _rarityText = string(abi.encodePacked(_totalMinted.toString(), " in existence"));
                }

                if (_gamePhase == DefifaGamePhase.SCORING) {
                    uint256 _potPortion = PRBMath.mulDiv(
                        _gamePot, _delegate.redemptionWeightOf(_tokenId), _delegate.TOTAL_REDEMPTION_WEIGHT()
                    );
                    _valueText = !_delegate.redemptionWeightIsSet()
                        ? "Awaiting scorecard..."
                        : _formatBalance(_potPortion, _gamePotToken, _gamePotDecimals, _IMG_DECIMAL_FIDELITY);
                } else {
                    _valueText = _formatBalance(_tier.price, _gamePotToken, _gamePotDecimals, _IMG_DECIMAL_FIDELITY);
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
                '<text x="10" y="30" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">GAME: ',
                _gameId.toString(),
                " | POT: ",
                _potText,
                " | PLAYERS: ",
                _delegate.store().totalSupply(address(_delegate)).toString(),
                "</text>",
                '<text x="10" y="50" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #ed017c;">',
                _gamePhaseText,
                "</text>",
                '<text x="10" y="85" style="font-size:26px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">',
                _getSubstring(_title, 0, 30),
                "</text>",
                '<text x="10" y="120" style="font-size:26px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">',
                _getSubstring(_title, 30, 60),
                "</text>",
                '<text x="10" y="205" style="font-size:80px; font-family: Capsules-700; font-weight:700; fill: #fea282;">',
                bytes(_getSubstring(_team, 20, 30)).length != 0 && bytes(_getSubstring(_team, 10, 20)).length != 0
                    ? _getSubstring(_team, 0, 10)
                    : "",
                "</text>",
                '<text x="10" y="295" style="font-size:80px; font-family: Capsules-700; font-weight:700; fill: #fea282;">',
                bytes(_getSubstring(_team, 20, 30)).length != 0
                    ? _getSubstring(_team, 10, 20)
                    : bytes(_getSubstring(_team, 10, 20)).length != 0 ? _getSubstring(_team, 0, 10) : "",
                "</text>",
                '<text x="10" y="385" style="font-size:80px; font-family: Capsules-700; font-weight:700; fill: #fea282;">',
                bytes(_getSubstring(_team, 20, 30)).length != 0
                    ? _getSubstring(_team, 20, 30)
                    : bytes(_getSubstring(_team, 10, 20)).length != 0
                        ? _getSubstring(_team, 10, 20)
                        : _getSubstring(_team, 0, 10),
                "</text>",
                '<text x="10" y="430" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">TOKEN ID: ',
                _tokenId.toString(),
                "</text>",
                '<text x="10" y="455" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">RARITY: ',
                _rarityText,
                "</text>",
                '<text x="10" y="480" style="font-size:16px; font-family: Capsules-500; font-weight:500; fill: #c0b3f1;">VALUE: ',
                _valueText,
                "</text>",
                "</svg>"
            )
        );
        parts[3] = string('"}');
        return string.concat(parts[0], Base64.encode(abi.encodePacked(parts[1], parts[2], parts[3])));
    }

    /**
     * @notice
     *   Gets a substring.
     *
     *   @dev
     *   If the first character is a space, it is not included.
     *
     *   @param _str The string to get a substring of.
     *   @param _startIndex The first index of the substring from within the string.
     *   @param _endIndex The last index of the string from within the string.
     *
     *   @return substring The substring.
     */
    function _getSubstring(string memory _str, uint256 _startIndex, uint256 _endIndex)
        internal
        pure
        returns (string memory substring)
    {
        bytes memory _strBytes = bytes(_str);
        if (_startIndex >= _strBytes.length) return "";
        if (_endIndex > _strBytes.length) _endIndex = _strBytes.length;
        _startIndex = _strBytes[_startIndex] == bytes1(0x20) ? _startIndex + 1 : _startIndex;
        if (_startIndex >= _endIndex) return "";
        bytes memory _result = new bytes(_endIndex-_startIndex);
        for (uint256 _i = _startIndex; _i < _endIndex;) {
            _result[_i - _startIndex] = _strBytes[_i];
            unchecked {
                ++_i;
            }
        }
        return string(_result);
    }

    /**
     * @notice
     *   Formats a balance from a fixed point number to a string.
     *
     *   @param _amount The fixed point amount.
     *   @param _token The token the amount is in.
     *   @param _decimals The number of decimals in the fixed point amount.
     *   @param _fidelity The number of decimals that should be returned in the formatted string.
     *
     *   @return The formatted balance.
     */
    function _formatBalance(uint256 _amount, address _token, uint256 _decimals, uint256 _fidelity)
        internal
        view
        returns (string memory)
    {
        bool _isEth = _token == JBTokens.ETH;

        uint256 _fixedPoint = 10 ** _decimals;

        // Convert amount to a decimal format
        string memory _integerPart = _amount.div(_fixedPoint).toString();
        string memory _decimalPart = _amount.mod(_fixedPoint).div(_fixedPoint.div(10 ** _fidelity)).toString();

        // Concatenate the strings
        return _isEth
            ? string(abi.encodePacked("\u039E", _integerPart, ".", _decimalPart))
            : string(abi.encodePacked(_integerPart, ".", _decimalPart, " ", IERC20Metadata(_token).symbol()));
    }
}
