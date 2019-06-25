pragma solidity ^0.5.0;

import './SnowflakeOwnable.sol';
import '../apis/datetimeapi.sol';
import '../components/DateTime.sol';

// TODO

// review SECURITY and allow certain functions to be called only by:
// - token
// - token owner
// (create a modifier for this)


/**
 * @title RulesEnforcer
 *
 * @notice Rules enforcement and registry of buyers
 *
 * @dev  This contract performs the following functions:
 *
 * 1. Default rules enforcer for Hydro security tokens
 *
 * 2. A buyer registry to hold EINs of buyers for any security token.
 * The Service Registry contract has an array of EINs, holds and provides information for buyers of any token, this simplifies the management of an ecosystems of buyers.
 *
 * @author Fatima Castiglione Maldonado <castiglionemaldonado@gmail.com>
 */

contract RulesEnforcer is SnowflakeOwnable {


    // token rules data

    struct rulesData {
        uint    minimumAge;
        uint64  minimumNetWorth;
        uint32  minimumSalary;
        bool    accreditedInvestorStatusRequired;
        bool    amlWhitelistingRequired;
        bool    cftWhitelistingRequired;
    }

    // token address => data to enforce rules
    mapping(address => rulesData) public tokenData;

    // token address => ISO country code => country is banned
    mapping(address => mapping(bytes32 => bool)) public bannedCountries;


    // buyer rules data

    DateTime dateTime;

    struct buyerData {
        string  firstName;
        string  lastName;
        bytes32 isoCountryCode;
        uint    birthTimestamp;
        uint64  netWorth;
        uint32  salary;
        bool    accreditedInvestorStatus;
        bool    kycWhitelisted;
        bool    amlWhitelisted;
        bool    cftWhitelisted;
    }

    struct buyerServicesDetail {
        bytes32  kycProvider;
        bytes32  amlProvider;
    }

    // buyer EIN => buyer data
    mapping(uint => buyerData) public buyerRegistry;

    // buyer EIN => token address => service details for buyer
    mapping(uint => mapping(address => buyerServicesDetail)) public serviceDetailForBuyers;


    // SnowflakeOwnable data

    address _identityRegistryAddress;


    // rules events

    /**
    * @notice Triggered when rules data is added for a token
    */
    event TokenValuesAssigned(address _tokenAddress);

    /**
    * @notice Triggered when a country is banned for a token
    */
    event AddCountryBan(address _tokenAddress, bytes32 _isoCountryCode);

    /**
    * @notice Triggered when a country ban is lifted for a token
    */
    event LiftCountryBan(address _tokenAddress, bytes32 _isoCountryCode);

    // buyer events

    /**
    * @notice Triggered when buyer is added
    */
    event AddBuyer(uint _buyerEIN, string _firstName, string _lastName);

    /**
    * @notice Triggered when KYC service is added
    */
    event AddKYCServiceToBuyer(uint _buyerEIN, address _token, bytes32 _serviceCategory);

    /**
    * @notice Triggered when AML service is added
    */
    event AddAMLServiceToBuyer(uint _buyerEIN, address _token, bytes32 _serviceCategory);

    /**
    * @notice Triggered when KYC service is replaced
    */
    event ReplaceKYCServiceForBuyer(uint _buyerEIN, address _token, bytes32 _serviceCategory);

    /**
    * @notice Triggered when AML service is replaced
    */
    event ReplaceAMLServiceForBuyer(uint _buyerEIN, address _token, bytes32 _serviceCategory);


    /**
    * @dev Validate that a contract exists in an address received as such
    * Credit: https://github.com/Dexaran/ERC223-token-standard/blob/Recommended/ERC223_Token.sol#L107-L114
    * @param _addr The address of a smart contract
    */
    modifier isContract(address _addr) {
        uint length;
        assembly { length := extcodesize(_addr) }
        require(length > 0, "Address cannot be blank");
        _;
    }

    /**
    * @notice Constructor
    */
    constructor(address _dateTimeAddress) public {
        dateTime = DateTime(_dateTimeAddress);
    }

    // functions for buyer's registry

    /**
    * @notice Add a new buyer
    * @dev    This method is only callable by the contract's owner
    * @param _firstName First name of the buyer
    * @param _lastName Last name of the buyer
    * @param _isoCountryCode ISO country code of the buyer
    * @param _yearOfBirth Year of birth of the buyer
    * @param _monthOfBirth Month of birth of the buyer
    * @param _dayOfBirth Day of birth of the buyer
    * @param _netWorth Net worth declared by the buyer
    * @param _salary Salary declared by the buyer
    }   */
    function addBuyer(
        uint _buyerEIN,
        string memory _firstName,
        string memory _lastName,
        bytes32 _isoCountryCode,
        uint16 _yearOfBirth,
        uint8 _monthOfBirth,
        uint8 _dayOfBirth,
        uint64 _netWorth,
        uint32 _salary)
    public onlySnowflakeOwner {
        buyerData memory _bd;
        _bd.firstName = _firstName;
        _bd.lastName = _lastName;
        _bd.isoCountryCode = _isoCountryCode;
        _bd.birthTimestamp = dateTime.toTimestamp(_yearOfBirth, _monthOfBirth, _dayOfBirth);
        _bd.netWorth = _netWorth;
        _bd.salary = _salary;
        buyerRegistry[_buyerEIN] = _bd;
        emit AddBuyer(_buyerEIN, _firstName, _lastName);
    }

    /**
    * @notice Add a new KYC service for a buyer
    *
    * @param _EIN EIN of the buyer
    * @param _tokenFor Token that uses this service
    * @param _serviceCategory For this buyer and this token, the service category to use for KYC
    */
    function addKYCServiceToBuyer(
        uint _EIN,
        address _tokenFor,
        bytes32 _serviceCategory)
    public isContract(_tokenFor) {
        bytes32 _emptyStringTest = _serviceCategory;
        require (_emptyStringTest.length != 0, "Service category cannot be blank");
        serviceDetailForBuyers[_EIN][_tokenFor].kycProvider = _serviceCategory;
        emit AddKYCServiceToBuyer(_EIN, _tokenFor, _serviceCategory);
    }

    /**
    * @notice Add a new AML service for a buyer
    *
    * @param _EIN EIN of the buyer
    * @param _tokenFor Token that uses this service
    * @param _serviceCategory For this buyer and this token, the service category to use for AML
    */
    function addAMLServiceToBuyer(
        uint _EIN,
        address _tokenFor,
        bytes32 _serviceCategory)
    public isContract(_tokenFor) {
        bytes32 _emptyStringTest = _serviceCategory;
        require (_emptyStringTest.length != 0, "Service category cannot be blank");
        serviceDetailForBuyers[_EIN][_tokenFor].amlProvider = _serviceCategory;
        emit AddAMLServiceToBuyer(_EIN, _tokenFor, _serviceCategory);
    }

    /**
    * @notice Replaces an existing KYC service for a buyer
    *
    * @dev This method is only callable by the contract's owner
    *
    * @param _EIN EIN of the buyer
    * @param _tokenFor Token that uses this service
    * @param _serviceCategory For this buyer and this token, the service category to use for KYC
    */
    function replaceKYCServiceForBuyer(
        uint _EIN,
        address _tokenFor,
        bytes32 _serviceCategory)
    public isContract(_tokenFor) {
        bytes32 _emptyStringTest = _serviceCategory;
        require (_emptyStringTest.length != 0, "Service category cannot be blank");
        serviceDetailForBuyers[_EIN][_tokenFor].kycProvider = _serviceCategory;
        emit ReplaceKYCServiceForBuyer(_EIN, _tokenFor, _serviceCategory);
    }

    /**
    * @notice Replaces an existing AML service for a buyer
    *
    * @dev This method is only callable by the contract's owner
    *
    * @param _EIN EIN of the buyer
    * @param _tokenFor Token that uses this service
    * @param _serviceCategory For this buyer and this token, the service category to use for KYC
    */
    function replaceAMLServiceForBuyer(
        uint _EIN,
        address _tokenFor,
        bytes32 _serviceCategory)
    public isContract(_tokenFor) {
        bytes32 _emptyStringTest = _serviceCategory;
        require (_emptyStringTest.length != 0, "Service category cannot be blank");
        serviceDetailForBuyers[_EIN][_tokenFor].amlProvider = _serviceCategory;
        emit ReplaceAMLServiceForBuyer(_EIN, _tokenFor, _serviceCategory);
    }

    // functions for rules enforcement

    /**
    * @notice Assign rule values for each token
    *
    * @dev This method is only callable by the contract's owner
    *
    * @param _tokenAddress Address for the Token
    * @param _minimumAge Required minimum age to buy this Token
    * @param _minimumNetWorth Required minimum net work to buy this Token
    * @param _minimumSalary Required minimum salary to buy this Token
    * @param _accreditedInvestorStatusRequired Determines if buyer must be an accredited investor to buy this Token
    */
    function assignTokenValues(
        address _tokenAddress,
        uint _minimumAge,
        uint64 _minimumNetWorth,
        uint32 _minimumSalary,
        bool _accreditedInvestorStatusRequired)
    public {
        tokenData[_tokenAddress].minimumAge = _minimumAge;
        tokenData[_tokenAddress].minimumNetWorth = _minimumNetWorth;
        tokenData[_tokenAddress].minimumSalary = _minimumSalary;
        tokenData[_tokenAddress].accreditedInvestorStatusRequired = _accreditedInvestorStatusRequired;
        emit TokenValuesAssigned(_tokenAddress);
    }

    /**
    * @notice TO DO
    *
    * @dev This method is only callable by the contract's owner
    *
    * @param _tokenAddress Address for the Token
    * @param _isoCountryCode Country to be banned for this Token
    */
    function addCountryBan(
        address _tokenAddress,
        bytes32 _isoCountryCode)
    public {
        bannedCountries[_tokenAddress][_isoCountryCode] = true;
        emit AddCountryBan(_tokenAddress, _isoCountryCode);
    }

    /**
    * @notice TO DO
    *
    * @dev This method is only callable by the contract's owner
    *
    * @param _tokenAddress Address for the Token
    * @param _isoCountryCode Country to be unbanned for this Token
    */
    function liftCountryBan(
        address _tokenAddress,
        bytes32 _isoCountryCode)
    public {
        bannedCountries[_tokenAddress][_isoCountryCode] = false;
        emit LiftCountryBan(_tokenAddress, _isoCountryCode);
    }

    /**
    * @notice Enforce rules for the investor
    *
    * @dev This method is only callable by a contract
    *
    * @param _buyerEIN EIN of the buyer
    */
    function checkRules(uint _buyerEIN) public view isContract(msg.sender) {
        // check if token has designated values
        bool _designatedDefaultValues = true;
        if ((tokenData[msg.sender].minimumAge == 0) ||
            (tokenData[msg.sender].minimumNetWorth == 0) ||
            (tokenData[msg.sender].minimumSalary == 0)) {
            _designatedDefaultValues = false;
            }
        require(_designatedDefaultValues == true, "Token must designated default values");

        // KYC restriction (not optional)
        require (buyerRegistry[_buyerEIN].kycWhitelisted == true, "Buyer must be approved for KYC");

        // AML restriction
        if (tokenData[msg.sender].amlWhitelistingRequired == true) {
            require (buyerRegistry[_buyerEIN].amlWhitelisted == true, "Buyer must be approved for AML");
        }

        // CFT restriction
        if (tokenData[msg.sender].cftWhitelistingRequired == true) {
            require (buyerRegistry[_buyerEIN].cftWhitelisted == true, "Buyer must be approved for CFT");
        }

        // age restriction
        if (tokenData[msg.sender].minimumAge > 0) {
            uint256 _buyerAgeSeconds = now - buyerRegistry[_buyerEIN].birthTimestamp;
            uint16 _buyerAgeYears = dateTime.getYear(_buyerAgeSeconds);
            require (_buyerAgeYears >= tokenData[msg.sender].minimumAge, "Buyer must reach minimum age");
        }

        // net-worth restriction
        if (tokenData[msg.sender].minimumNetWorth > 0) {
            require (buyerRegistry[_buyerEIN].netWorth >= tokenData[msg.sender].minimumNetWorth, "Buyer must reach minimum net worth");
        }

        // salary restriction
        if (tokenData[msg.sender].minimumSalary > 0) {
            require (buyerRegistry[_buyerEIN].salary >= tokenData[msg.sender].minimumSalary, "Buyer must  reach minimum salary");
        }

        // accredited investor status
        if (tokenData[msg.sender].accreditedInvestorStatusRequired == true) {
            require (buyerRegistry[_buyerEIN].accreditedInvestorStatus == true, "Buyer must be an accredited investor");
        }

        // country/geography restrictions on ownership
        require (bannedCountries[msg.sender][buyerRegistry[_buyerEIN].isoCountryCode] == false, "Country of Buyer must not be banned for token");

    }

}
