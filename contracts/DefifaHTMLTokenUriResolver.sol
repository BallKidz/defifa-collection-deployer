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
import {IScriptyBuilder, InlineScriptRequest, WrappedScriptRequest} from 'scripty.sol/contracts/scripty/IScriptyBuilder.sol';

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
contract DefifaHTMLTokenUriResolver is IDefifaTokenUriResolver, IJBTokenUriResolver {
  using Strings for uint256;

  //*********************************************************************//
  // -------------------- private constant properties ------------------ //
  //*********************************************************************//

  /**
    @notice
    The fidelity of the decimal returned in the NFT image.
  */
  uint256 private constant _IMG_DECIMAL_FIDELITY = 4;

  //*********************************************************************//
  // -------------------- Scripty.sol Kmac hacks ------------------ //
  //*********************************************************************//

  /** 
    @notice
    somebody that knows more than me should fix this
  */
  address private constant _SCRIPTY_STORAGE_ADDRESS = 0x096451F43800f207FC32B4FF86F286EdaF736eE3;
  address private constant _SCRIPTY_BUILDER_ADDRESS = 0x16b727a2Fc9322C724F4Bc562910c99a5edA5084;
  address private constant _ETHFS_FILESTORAGE_ADDRESS = 0xFc7453dA7bF4d0c739C1c53da57b3636dAb0e11e;
  uint256 public constant BUFFER_SIZE = 1000000;

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

  //*********************************************************************//
  // -------------------- public stored properties --------------------- //
  //*********************************************************************//

  IDefifaDelegate public override delegate;

  ITypeface public override typeface;

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

  /** 
    @notice
    Helper functions for parsing tokenUri to get image ipfs hash. Currently unused.

    @dev TODO If parsing in sol js must be changed too 
  */

  function parseIpfsPath(string memory ipfsPath) internal pure returns (string memory image) {
    bytes memory decoded = bytes(ipfsPath);
    // Extract the name, description, image, and external URL
    image = extractString(bytes(ipfsPath), 64, 96);
  }
  
  function extractString(bytes memory data, uint256 start, uint256 end) internal pure returns (string memory) {
    bytes memory result = new bytes(end - start);
    for (uint256 i = start; i < end; i++) {
      result[i - start] = data[i];
    }
    return string(result);
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

    @param _delegate The Defifa delegate contract that this contract is Governing.
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

    // Get a reference to the tier.
    JB721Tier memory _tier = _delegate.store().tierOfTokenId(address(_delegate), _tokenId, false);

    // Scripty builder
    WrappedScriptRequest[] memory requests = new WrappedScriptRequest[](3);

    requests[0].name = 'p5-v1.5.0.min.js.gz';
    requests[0].wrapType = 2; // <script type="text/javascript+gzip" src="data:text/javascript;base64,[script]"></script>
    requests[0].contractAddress = _ETHFS_FILESTORAGE_ADDRESS;

    requests[1].name = 'gunzipScripts-0.0.1.js';
    requests[1].wrapType = 1; // <script src="data:text/javascript;base64,[script]"></script>
    requests[1].contractAddress = _ETHFS_FILESTORAGE_ADDRESS;

    // Set 'global' variables and add prior to script written in p5.js
    string memory _titleFontSize;
    string memory _title = _delegate.name();
    string memory _team = _tierNameOf[_tier.id];

    if (bytes(_title).length < 35) _titleFontSize = '20';
    else _titleFontSize = '16';

    string memory _fontSize;
    if (bytes(_team).length < 3) _fontSize = '40';
    else if (bytes(_team).length < 5) _fontSize = '40';
    else if (bytes(_team).length < 8) _fontSize = '40';
    else if (bytes(_team).length < 10) _fontSize = '40';
    else if (bytes(_team).length < 12) _fontSize = '40';
    else if (bytes(_team).length < 16) _fontSize = '40';
    else if (bytes(_team).length < 23) _fontSize = '40';
    else if (bytes(_team).length < 30) _fontSize = '30';
    else if (bytes(_team).length < 35) _fontSize = '20';
    else _fontSize = '16';

    // Get the current game phase.
    uint256 _gamePhase = _delegate.fundingCycleStore().currentOf(delegate.projectId()).number;
    string memory _gamePhaseText;

    {
      string memory _percentOfPot = DefifaPercentFormatter.getFormattedPercentageOfRedemptionWeight(
        _delegate.redemptionWeightOf(_tokenId),
        _delegate.TOTAL_REDEMPTION_WEIGHT(),
        _IMG_DECIMAL_FIDELITY
      );

      if (_gamePhase == 0) _gamePhaseText = 'Minting starts soon.';
      else if (_gamePhase == 1) _gamePhaseText = 'Starting soon, minting and refunds are open.';
      else if (_gamePhase == 2) _gamePhaseText = 'Starts soon. Last chance for refund.';
      else if (_gamePhase == 3) _gamePhaseText = 'Game in progress.';
      else if (_gamePhase == 4 && _delegate.redemptionWeightIsSet())
        _gamePhaseText = 'Scorecard awaiting approval.';
      else _gamePhaseText = string.concat('Redeem for ', _percentOfPot, ' of the pot.');
    }
    string memory _rarityText;
    {
      uint256 _totalMinted = _tier.initialQuantity - _tier.remainingQuantity;
      if (_gamePhase == 1)
        _rarityText = string(abi.encodePacked(_totalMinted.toString(), ' minted so far'));
      else _rarityText = string(abi.encodePacked(_totalMinted.toString(), ' in existence'));
    }

    bytes32 _encodedTierIPFSUri = _delegate.store().encodedTierIPFSUriOf(
      address(_delegate),
      _tokenId
    );
    string memory artWorkIPFS = _encodedTierIPFSUri.length != 0
      ? JBIpfsDecoder.decode(_delegate.baseURI(), _encodedTierIPFSUri)
      : 'QmP5eWnXTsRCWBeDrHboLtFeuhjVLNEHb6np7DiYN7uZyx'; // 404 ipfs img.
    // TODO @dev can we remove this and put into create flow?
    string memory scoreCardIPFS = 'QmeB47KfbHetHPpQrPgmD9CxCDb9e2U9j9fxLr1FM3vzMo';
    string memory buttonImageIPFS = 'QmdpL1xN4cAHQw4P1FZzw9P3oQofA8h45PfuTTbpV4BbJV';

    bytes memory controllerScript = abi.encodePacked(
      'let artWorkSource ="',
      artWorkIPFS,
      '";',
      'let scoreCardIPFS ="',
      scoreCardIPFS,
      '";',
      'let buttonImageIPFS ="',
      buttonImageIPFS,
      '";',
      'let txt_1 ="',
      _title,
      '".toUpperCase();let txt_1Size =',
      _titleFontSize,
      ';let txt_1Color = "#17e4f1";let txt_1_x = 40;let txt_1_y = 80;',
      'let txt_2 ="GAME PHASE ',
      _gamePhase.toString(),
      ' of 4',
      '";let txt_2Size = 20;let txt_2Color = "#17e4f1";let txt_2_x = 40;let txt_2_y = 220;',
      'let txt_3 ="',
      _gamePhaseText,
      '";let txt_3Size = 20;let txt_3Color = "#fea282";let txt_3_x = 40;let txt_3_y = 250;',
      'let txt_4 ="',
      _team,
      '";let txt_4Size =',
      _fontSize,
      ';let txt_4Color = "#fea282";let txt_4_x = 40;let txt_4_y = 130;',
      'let txt_5 ="TOKEN ID: ',
      _tokenId.toString(),
      '";let txt_5Size = 16;let txt_5Color = "#FFFFFF";let txt_5_x = 40;let txt_5_y = 370;',
      'let txt_6 ="RARITY: ',
      _rarityText,
      '";let txt_6Size = 16;let txt_6Color = "#FFFFFF";let txt_6_x = 40;let txt_6_y = 400;',
      'let font = "data:font/truetype;charset=utf-8;base64,',
      DefifaFontImporter.getSkinnyFontSource(typeface),
      '";',
      // TODO remove line below and put file on chain eg ethfs.xyz, calc buffer size
      'let page,camLoc,buttL,buttR,timer,buttonImg,pages=[],numOfPages=2,movingRight=!1,movingLeft=!1,isPaused=!1,artWorkPanel="https://jbm.infura-ipfs.io/ipfs/",scoreCardPanel="https://jbm.infura-ipfs.io/ipfs/"+scoreCardIPFS,buttonImage="https://jbm.infura-ipfs.io/ipfs/"+buttonImageIPFS,defifaBlue=[19,228,240],txt1=[[txt_1,txt_1Color,txt_1Size]],txt2=[[txt_2,txt_2Color,txt_2Size]],txt3=[[txt_3,txt_3Color,txt_3Size]],txt4=[[txt_4,txt_4Color,txt_4Size]],txt5=[[txt_5,txt_5Color,txt_5Size]],txt6=[[txt_6,txt_6Color,txt_6Size]],pageImg=[];function preload(){async function a(a){let c=await fetch("https://jbm.infura-ipfs.io/ipfs/"+a);console.log(b);const d=c.headers.get("content-type");console.log(d),d&&-1!==d.indexOf("application/json")?(b=await c.json(),pageImg[0]=loadImage(b.image)):(artWorkPanel="https://jbm.infura-ipfs.io/ipfs/"+a,pageImg[0]=loadImage(artWorkPanel),console.log(artWorkPanel))}let b;a(artWorkSource),pageImg[1]=loadImage(scoreCardPanel),buttonImg=loadImage(buttonImage)}function setup(){myFont=loadFont(font),createCanvas(500,500),camLoc=createVector(0,0);for(let a=0;a<numOfPages;a++)pages[a]=new Page(canvas.width/2*a,0,a,pageImg[a]);timer=canvas.width/2,buttL=new Button(canvas.width/2-90,5,75,75,buttonImg),buttR=new Button(canvas.width/2-90,5,75,75,buttonImg)}function draw(){background(220),slide(),push(),translate(camLoc.x,camLoc.y);for(let a=0;a<numOfPages;a++)pages[a].run();pop(),buttL.run(),buttR.run()}function goRight(){movingLeft||isPaused||(movingRight=!0)}function goLeft(){movingRight||isPaused||(movingLeft=!0)}function slide(){movingRight&&!movingLeft&&0<=timer&&(camLoc.x-=20,timer-=20),movingLeft&&!movingRight&&0<=timer&&(camLoc.x+=20,timer-=20),0==timer&&(movingRight=!1,movingLeft=!1,timer=canvas.width/2),0>=-camLoc.x?(camLoc.x=0,buttL.loc.x=-100):buttL.loc.x=canvas.height/2-75,-camLoc.x>=pages[pages.length-1].loc.x?(timer=canvas.width/2,movingRight=!1,movingLeft=!1,camLoc.x=-pages[pages.length-1].loc.x,buttR.loc.x=-100):buttR.loc.x=canvas.height/2-75}function drawtext(a,b,d){for(var e=a,f=0;f<d.length;++f){var g=d[f],h=g[0],j=g[1],c=g[2],k=textWidth(h);fill(j),textSize(c),text(h,e,b),e+=k}}function mousePressed(){mouseX>buttL.loc.x&&mouseX<buttL.loc.x+buttL.w&&mouseY>buttL.loc.y&&mouseY<buttL.loc.y+buttL.h&&goLeft(),mouseX>buttR.loc.x&&mouseX<buttR.loc.x+buttR.w&&mouseY>buttR.loc.y&&mouseY<buttR.loc.y+buttR.h&&goRight()}class Page{constructor(a,b,c,d){this.loc=createVector(a,b),this.w=canvas.width/2,this.h=canvas.height/2,this.pageNum=c+1,this.img=d}run(){image(this.img,this.loc.x,this.loc.y,500,500),textAlign(LEFT),textFont(myFont),2==this.pageNum&&(drawtext(this.loc.x+txt_1_x,this.loc.y+txt_1_y,txt1),drawtext(this.loc.x+txt_2_x,this.loc.y+txt_2_y,txt2),drawtext(this.loc.x+txt_3_x,this.loc.y+txt_3_y,txt3),drawtext(this.loc.x+txt_4_x,this.loc.y+txt_4_y,txt4),drawtext(this.loc.x+txt_5_x,this.loc.y+txt_5_y,txt5),drawtext(this.loc.x+txt_6_x,this.loc.y+txt_6_y,txt6));3==this.pageNum,line(this.loc.x,this.loc.y,this.loc.x+this.w,this.loc.y),line(this.loc.x,this.loc.y,this.loc.x,this.loc.y+this.h),line(this.loc.x,this.loc.y+this.h,this.loc.x+this.w,this.loc.y+this.h),line(this.loc.x+this.w,this.loc.y,this.loc.x+this.w,this.h)}}class Button{constructor(a,b,c,d,e){this.loc=new createVector(a,b),this.w=c,this.h=d,this.clr="white",this.img=e}run(){this.render(),this.checkMouse()}render(){fill(this.clr),stroke(20),strokeWeight(0),fill("black"),noStroke(),textSize(15),image(this.img,this.loc.x,this.loc.y,this.w,this.h)}checkMouse(){this.clr=mouseX>this.loc.x&&mouseX<this.loc.x+this.w&&mouseY>this.loc.y&&mouseY<this.loc.y+this.h?"gray":"white"}}'
    );
    requests[2].scriptContent = controllerScript;
    //requests[3].name = 'defifa_scorecard_min.0.0.1.js';
    //requests[3].contractAddress = _ETHFS_FILESTORAGE_ADDRESS;
    //requests[3].wrapType = 1;
    // For easier testing, bufferSize for statically stored scripts
    // is injected in the constructor. Then controller script's length
    // is added to that to find the final buffer size.

    uint256 finalBufferSize = BUFFER_SIZE + controllerScript.length;
    // For easier testing, bufferSize is injected in the constructor
    // of this contract.

    bytes memory base64EncodedHTMLDataURI = IScriptyBuilder(_SCRIPTY_BUILDER_ADDRESS)
      .getEncodedHTMLWrapped(requests, finalBufferSize);

    bytes memory metadata = abi.encodePacked(
      '{"name":"',
      _title,
      '","description":"Team: ',
      _team,
      ', ID: ',
      _tier.id.toString(),
      '","animation_url":"',
      base64EncodedHTMLDataURI,
      '"}'
    );

    return string(abi.encodePacked('data:application/json;base64,', Base64.encode(metadata)));
  }
}
