pragma solidity ^0.5.0;

import './components/SnowflakeOwnable.sol';
//import './components/TokenWithDates.sol';
import './interfaces/HydroInterface.sol';
import './interfaces/ApproverInterface.sol';
import './interfaces/IdentityRegistryInterface.sol';
import './interfaces/SnowflakeViaInterface.sol';
import './zeppelin/math/SafeMath.sol';
import './zeppelin/ownership/Ownable.sol';

// Rinkeby testnet addresses
// HydroToken: 0x4959c7f62051d6b2ed6eaed3aaee1f961b145f20
// IdentityRegistry: 0xa7ba71305be9b2dfead947dc0e5730ba2abd28ea

// TODO
//
// A global Registry with data of all Securities issued, to check for repeated ids or symbols
//
// Feature #11: Participant functions -> send and receive token
// Feature #15: Carried interest ?
// Feature #16: Interest payout ?
// Feature #17: Dividend payout ?


/**
 * @title HSTIssuer
 * @notice The Hydro Security Token is a system to allow people to create their own Security Tokens, 
 *         related to their Snowflake identities and attached to external KYC, AML and other rules.
 * @author Juan Livingston <juanlivingston@gmail.com>
 */

contract HSTIssuer {

    using SafeMath for uint256;
    
    enum Stage {
        SETUP, PRELAUNCH, ACTIVE, FINALIZED
    }

    // For date analysis
    struct Batch {
        uint initial; // Initial quantity received in a batch. Not modified in the future
        uint quantity; // Current quantity of tokens in a batch.
        uint age; // Birthday of the batch (timestamp)
    }

	// Main parameters
	uint256 public id;
	string public name;
	string public description;
	string public symbol;
    uint8 public decimals;
    address payable public Owner;
    uint256 einOwner;

  /**
  * @notice Variables are grouped into arrays accesed by enums, because Solidity can not habdle so many individual variables
  */

    bool[7] public MAIN_PARAMS;
    enum MP {
    	hydroPrice,
        ethPrice,
    	beginningDate,
        lockEnds, // Date of end of locking period
    	endDate,
        maxSupply,
        escrowLimitPeriod
    }


	// STO types / flags
    bool[10] public STO_FLAGS;
    enum SF {
        LIMITED_OWNERSHIP, 
        IS_LOCKED, // Locked token transfers
        PERIOD_LOCKED,  // Locked period active or inactive
        PERC_OWNERSHIP_TYPE, // is ownership percentage limited type
        HYDRO_AMOUNT_TYPE, // is Hydro amount limited
        ETH_AMOUNT_TYPE, // is Ether amount limited
        HYDRO_ALLOWED, // Is Hydro allowed to purchase
        ETH_ALLOWED, // Is Ether allowed for purchase
        KYC_WHITELIST_RESTRICTED, 
        AML_WHITELIST_RESTRICTED
    }

    uint256[6] public STO_PARAMS;
    enum SP {
        percAllowedTokens, // considered if PERC_OWNERSHIP_TYPE
        hydroAllowed, // considered if HYDRO_AMOUNT_TYPE
        ethAllowed, // considered if ETH_AMOUNT_TYPE
        lockPeriod, // in days
        minInvestors,
        maxInvestors
    }

    // State Memory
    Stage public stage; // SETUP, PRELAUNCH, ACTIVE, FINALIZED
    bool legalApproved;
    uint256 issuedTokens;
    uint256 public ownedTokens;
    uint256 public burnedTokens;
    uint256 public hydroReceived;
    uint256 public ethReceived;
    uint256 hydrosReleased; // Quantity of Hydros released by owner
    uint256 ethersReleased; // idem form Ethers

 	// Links to Modules
 	address HSToken;
	address RegistryRules;

	// Links to Registries
    address[5] public KYCResolverArray;
    address[5] public AMLResolverArray;
    address[5] public LegalResolverArray;
    mapping(address => uint8) public KYCResolver;
    mapping(address => uint8) public AMLResolver;
    mapping(address => uint8) public LegalResolver;
    uint8 KYCResolverQ;
    uint8 AMLResolverQ;
    uint8 LegalResolverQ;

    address InterestSolver;

    // Mappings
    mapping(uint256 => bool) public whiteList;
    mapping(uint256 => bool) public blackList;
    mapping(uint256 => bool) public freezed;

    mapping(address => uint256) public balance;

    // For date analysis and paying interests
    mapping(address => uint) public maxIndex; // Index of last batch: points to the next one
    mapping(address => uint) public minIndex; // Index of first batch
    mapping(address => mapping(uint => Batch)) public batches; // Batches with quantities and ages

    // Escrow contract's address => security number
    mapping(address => uint256) public escrowContracts;
    address[] public escrowContractsArray;

    // Declaring interfaces
    IdentityRegistryInterface public identityRegistry;
    HydroInterface public hydroToken;
    // SnowflakeViaInterface public snowflakeVia;
    // TokenWithDates private tokenWithDates;


    event HydroSTCreated(
        uint256 indexed id, 
        string name,
        string symbol,
        uint8 decimals,
        uint256 einOwner
        );

    event Sell(address indexed _owner, uint256 _amount);


    // Feature #9 & #10
    modifier isUnlocked() {
        require(!STO_FLAGS[SF.IS_LOCKED], "Token locked");
        if (STO_FLAGS[SF.PERIOD_LOCKED]) require (now > MAIN_PARAMS[MP.lockEnds], "Locked period active");
        _;
    }

    modifier isUnfreezed(address _from, address _to) {
        require(!freezed[identityRegistry.getEIN(_to)] , "Target EIN is freezed");
        require(!freezed[identityRegistry.getEIN(_from)], "Source EIN is freezed");
        _;
    }

    modifier onlyAtPreLaunch() {
        require(stage == Stage.PRELAUNCH, "Not in Prelaunch stage");
    	_;
    }

    modifier onlyActive() {
        require(stage == Stage.ACTIVE, "Not active");
        _;
    }

    modifier onlyAdmin() {
        // Check if EIN of sender is the same as einOwner
        require(identityRegistry.getEIN(msg.sender) == einOwner, "Only for admins");
        _;
    }

    modifier escrowReleased() {
        require(MAIN_PARAMS[MP.escrowLimitPeriod] < now, "Escrow limit period is still active");
        require(legalApproved, "Legal conditions are not met");
        _;
    }

    constructor(
        uint256 _id,
        string memory _name,
        string memory _description,
        string memory _symbol,
        uint8 _decimals,

        uint256[7] memory _MAIN_PARAMS,
        bool[10] memory _STO_FLAGS,
        uint256[6] memory _STO_PARAMS

        ) public {

        id = _id; 
        name = _name;
        description = _description;
        symbol = _symbol;
        decimals = _decimals;

        MAIN_PARAMS[] = _MAIN_PARAMS;

        // STO types / flags
        STO_FLAGS[] = _STO_FLAGS; // _LIMITED_OWNERSHIP;

        // STO parameters
        STO_PARAMS[] = _STO_PARAMS;

        // State Memory
        stage = Stage.SETUP;

        // Links to Modules
        HSToken = 0x4959c7f62051D6b2ed6EaeD3AAeE1F961B145F20;
        RegistryRules = 0x4959c7f62051D6b2ed6EaeD3AAeE1F961B145F20;
        InterestSolver = address(0x0);

        hydroToken = HydroInterface(0x4959c7f62051D6b2ed6EaeD3AAeE1F961B145F20);
        identityRegistry = IdentityRegistryInterface(0xa7ba71305bE9b2DFEad947dc0E5730BA2ABd28EA);

        Owner = msg.sender;
        einOwner = identityRegistry.getEIN(Owner);

        emit HydroSTCreated(id, name, symbol, decimals, einOwner);
    }

    // Feature #10: ADMIN FUNCTIONS

    // Feature #9
    function setLockupPeriod(uint256 _lockEnds) onlyAdmin public {
        if (_lockEnds == 0) {
            STO_FLAGS[SF.PERIOD_LOCKED] = false;
            }
        STO_FLAGS[SF.PERIOD_LOCKED] = true;
        MAIN_PARAMS[MP.lockEnds] = _lockEnds;
    }

    function lock() onlyAdmin public {
        STO_FLAGS[SF.IS_LOCKED] = true;
    }

    function unLock() onlyAdmin public {
        STO_FLAGS[SF.IS_LOCKED] = false;
    }

    function addWhitelist(uint256[] memory _einList) onlyAdmin public {
        for (uint i = 0; i < _einList.length; i++) {
          whiteList[_einList[i]] = true;
        }
    }

    function addBlackList(uint256[] memory _einList) onlyAdmin public {
        for (uint i = 0; i < _einList.length; i++) {
          blackList[_einList[i]] = true;
        }
    }

    function removeWhitelist(uint256[] memory _einList) onlyAdmin public {
        for (uint i = 0; i < _einList.length; i++) {
          whiteList[_einList[i]] = false;
        }

    }

    function removeBlacklist(uint256[] memory _einList) onlyAdmin public {
        for (uint i = 0; i < _einList.length; i++) {
          blackList[_einList[i]] = false;
        }
    }

    function freeze(uint256[] memory _einList) onlyAdmin public {
        for (uint i = 0; i < _einList.length; i++) {
          freezed[_einList[i]] = true;
        }
    }

    function unFreeze(uint256[] memory _einList) onlyAdmin public {
        for (uint i = 0; i < _einList.length; i++) {
          freezed[_einList[i]] = false;
        }
    }


    // Only at Prelaunch functions: adding and removing resolvers

    // Feature #3
    function addKYCResolver(address[] memory _address) onlyAdmin onlyAtPreLaunch public {
        require(KYCResolver[_address[0]] == 0, "Resolver already exists");
        require(KYCResolverQ <= 5, "No more resolvers allowed");
        identityRegistry.addResolvers(_address);
        KYCResolverQ ++;
        KYCResolver[_address[0]] = KYCResolverQ;
        KYCResolverArray[KYCResolverQ-1] = _address[0];
    }

    function removeKYCResolver(address[] memory _address) onlyAdmin onlyAtPreLaunch public {
        require(KYCResolver[_address[0]] != 0, "Resolver does not exist");
        uint8 _number = KYCResolver[_address[0]];
        if (KYCResolverArray.length > _number) {
            for (uint8 i = _number; i < KYCResolverArray.length; i++) {
                KYCResolverArray[i-1] = KYCResolverArray[i];
            }
        }
        KYCResolverArray[KYCResolverQ - 1] = address(0x0);
        KYCResolverQ --;
        KYCResolver[_address[0]] = 0;
        identityRegistry.removeResolvers(_address); 
    }
    function addAMLResolver(address[] memory _address) onlyAdmin onlyAtPreLaunch public {
        require(AMLResolver[_address[0]] == 0, "Resolver already exists");
        require(AMLResolverQ <= 5, "No more resolvers allowed");
        identityRegistry.addResolvers(_address);
        AMLResolverQ ++;
        AMLResolver[_address[0]] = AMLResolverQ;
        AMLResolverArray[AMLResolverQ-1] = _address[0];
    }

    function removeAMLResolver(address[] memory _address) onlyAdmin onlyAtPreLaunch public {
        require(AMLResolver[_address[0]] != 0, "Resolver does not exist");
        uint8 _number = AMLResolver[_address[0]];
        if (AMLResolverArray.length > _number) {
            for (uint8 i = _number; i < AMLResolverArray.length; i++) {
                AMLResolverArray[i-1] = AMLResolverArray[i];
            }
        }
        AMLResolverArray[AMLResolverQ - 1] = address(0x0);
        AMLResolverQ --;
        AMLResolver[_address[0]] = 0;
        identityRegistry.removeResolvers(_address); 
    }
    function addLegalResolver(address[] memory _address) onlyAdmin onlyAtPreLaunch public {
        require(LegalResolver[_address[0]] == 0, "Resolver already exists");
        require(LegalResolverQ <= 5, "No more resolvers allowed");
        identityRegistry.addResolvers(_address);
        LegalResolverQ ++;
        LegalResolver[_address[0]] = LegalResolverQ;
        LegalResolverArray[LegalResolverQ-1] = _address[0];
    }

    function removeLegalResolver(address[] memory _address) onlyAdmin onlyAtPreLaunch public {
        require(LegalResolver[_address[0]] != 0, "Resolver does not exist");
        uint8 _number = LegalResolver[_address[0]];
        if (LegalResolverArray.length > _number) {
            for (uint8 i = _number; i < LegalResolverArray.length; i++) {
                LegalResolverArray[i-1] = LegalResolverArray[i];
            }
        }
        LegalResolverArray[LegalResolverQ - 1] = address(0x0);
        LegalResolverQ --;
        LegalResolver[_address[0]] = 0;
        identityRegistry.removeResolvers(_address); 
    }




    // Release gains. Only after escrow is released

    // Retrieve tokens and ethers
    function releaseHydroTokens() onlyAdmin escrowReleased public {
        uint256 thisBalance = hydroToken.balanceOf(address(this));
        hydrosReleased = hydrosReleased + thisBalance;
        require(hydroToken.transfer(Owner, thisBalance));
    }

    function releaseEthers() onlyAdmin escrowReleased public {
        ethersReleased = ethersReleased + address(this).balance;
        require(Owner.send(address(this).balance));
    }




    // PUBLIC FUNCTIONS FOR INVESTORS -----------------------------------------------------------------


    function buyTokens(string memory _coin, uint256 _amount) onlyActive
        public payable returns(bool) {

        uint256 total;
        //uint256 _ein = identityRegistry.getEIN(msg.sender);
        bytes32 HYDRO = keccak256(abi.encode("HYDRO"));
        bytes32 ETH =  keccak256(abi.encode("ETH"));
        bytes32 coin = keccak256(abi.encode(_coin));

        require(stage == Stage.ACTIVE, "Current stage is not active");

        // CHECKINGS (to be exported as  a contract)
        // Coin allowance
        if (coin == HYDRO) require (STO_FLAGS[SF.HYDRO_ALLOWED], "Hydro is not allowed");
        if (coin == ETH) require (STO_FLAGS[SF.ETH_ALLOWED], "Ether is not allowed");
        // Check for limits
        if (STO_FLAGS [SF.HYDRO_AMOUNT_TYPE] && coin == HYDRO) {
            require(hydroReceived.add(_amount) <= STO_PARAMS[SP.hydroAllowed], "Hydro amount exceeded");
        }
        if (STO_FLAGS [SF.ETH_AMOUNT_TYPE] && coin == ETH) {
            require((ethReceived + msg.value) <= STO_PARAMS[SP.ethAllowed], "Ether amount exceeded");
        }
        // Check for whitelists
        if (STO_FLAGS [SF.KYC_WHITELIST_RESTRICTED]) _checkKYCWhitelist(msg.sender, _amount);
        if (STO_FLAGS [SF.AML_WHITELIST_RESTRICTED]) _checkAMLWhitelist(msg.sender, _amount);
        // Calculate total
        if (coin == HYDRO) {
            total = _amount.mul(MAIN_PARAMS[MP.hydroPrice]);
            hydroReceived = hydroReceived.add(_amount);      
        }

        if (coin == ETH) {
            total = msg.value.mul(MAIN_PARAMS[MP.ethPrice]);
            ethReceived = ethReceived + msg.value;
        }
        // Check for ownership percentage 
        if (STO_FLAGS [SF.PERC_OWNERSHIP_TYPE]) {
            require ((issuedTokens.add(total) / ownedTokens) < STO_PARAMS[SP.percAllowedTokens], 
                "Perc ownership exceeded");
        }
        // Transfer Hydrotokens
        if (coin == HYDRO) {
            require(hydroToken.transferFrom(msg.sender, address(this), _amount), 
                "Hydro transfer was nos possible");
        }

        // Sell
        _doSell(msg.sender, total);
        emit Sell(msg.sender, total);
        return true;
    }


    function claimInterests() 
        public pure returns(bool) {
        //return(interestSolver(msg.sender));
        return true;
    }



    // Token ERC-20 wrapper -----------------------------------------------------------

    // Feature #11
    function transfer(address _to, uint256 _amount) 
        isUnlocked isUnfreezed(msg.sender, _to) 
        public returns(bool) {
        
        if (STO_FLAGS [SF.KYC_WHITELIST_RESTRICTED]) _checkKYCWhitelist(_to, _amount);
        if (STO_FLAGS [SF.AML_WHITELIST_RESTRICTED]) _checkAMLWhitelist(_to, _amount);

        // _updateBatches(msg.sender, _to, _amount);

        return(hydroToken.transfer(_to, _amount));
    }

    // Feature #11
    function transferFrom(address _from, address _to, uint256 _amount) 
        isUnlocked isUnfreezed(_from, _to) 
        public returns(bool) {
        
        if (STO_FLAGS [SF.KYC_WHITELIST_RESTRICTED]) _checkKYCWhitelist(_to, _amount);
        if (STO_FLAGS [SF.AML_WHITELIST_RESTRICTED]) _checkAMLWhitelist(_to, _amount);

        // _updateBatches(_from, _to, _amount);

        return(hydroToken.transferFrom(_from, _to, _amount));
    }




    // PUBLIC GETTERS ----------------------------------------------------------------

    function isLocked() public view returns(bool) {
        return STO_FLAGS[SF.IS_LOCKED];
    }




    // INTERNAL FUNCTIONS ----------------------------------------------------------

     function _doSell(address _to, uint256 _amount) private {
        issuedTokens = issuedTokens + _amount;
        ownedTokens = ownedTokens + _amount;
        balance[_to].add(_amount);
    }


    // Permissions checking

    // Feature #8
    function _checkKYCWhitelist(address _to, uint256 _amount) private view {
        uint256 einTo = identityRegistry.getEIN(_to);

        for (uint8 i = 1; i <= KYCResolverQ; i++) {
            ApproverInterface approver = ApproverInterface(KYCResolverArray[i-1]);
            require(approver.isApproved(einTo, _amount));
        }
    }
    function _checkAMLWhitelist(address _to, uint256 _amount) private view {
        uint256 einTo = identityRegistry.getEIN(_to);

        for (uint8 i = 1; i <= AMLResolverQ; i++) {
            ApproverInterface approver = ApproverInterface(AMLResolverArray[i-1]);
            require(approver.isApproved(einTo, _amount));
        }
    }
    function _checkLegalWhitelist(address _to, uint256 _amount) private view {
        uint256 einTo = identityRegistry.getEIN(_to);

        for (uint8 i = 1; i <= LegalResolverQ; i++) {
            ApproverInterface approver = ApproverInterface(LegalResolverArray[i-1]);
            require(approver.isApproved(einTo, _amount));
        }
    }

}
