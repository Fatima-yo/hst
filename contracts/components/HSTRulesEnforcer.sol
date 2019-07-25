pragma solidity ^0.5.0;

import './SnowflakeOwnable.sol';
import '../components/DateTime.sol';
import '../components/HSTServiceRegistry.sol';
import '../HSTokenRegistry.sol';


// TODO

// review SECURITY and allow certain functions to be called only by:
// - token
// - token owner
// (create a modifier for this)


/**
 * @title HSTRulesEnforcer
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

contract HSTRulesEnforcer {
// is SnowflakeOwnable {


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


    // external

    DateTime dateTime;
    HSTServiceRegistry hstServiceRegistry;
    HSTokenRegistry hstokenRegistry;


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
    *
    * @param _dateTimeAddress address for the date time contract
    */
    constructor(address _dateTimeAddress) public {
        dateTime = DateTime(_dateTimeAddress);
    }


    // functions for contract configuration

    /**
    * @notice configure this contract
    * @dev this contract need to communicate with token and service registries
    *
    * @param _tokenRegistryAddress The address for the token registry
    * @param _serviceRegistryAddress The address for the service registry
    *
    */
    function setAddresses(address _tokenRegistryAddress, address _serviceRegistryAddress) public {
        hstokenRegistry = HSTokenRegistry(_tokenRegistryAddress);
        hstServiceRegistry = HSTServiceRegistry(_serviceRegistryAddress);
    }


    // functions for checking other registries
    // TO DO

    function registeredToken() internal pure returns(bool) {
        return true;
    }

    function registeredProvider() internal pure returns(bool) {
        return true;
    }


    // functions for token rules update

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
    * @notice get token rules data
    *
    * @param _tokenAddress Address for the Token
    * @return minimum age required to buy this token
    */
    function getTokenMinimumAge(address _tokenAddress) public view returns (uint) {
        return tokenData[_tokenAddress].minimumAge;
    }

    /**
    * @notice get token rules data
    *
    * @param _tokenAddress Address for the Token
    * @return minimum net worth required to buy this token
    */
    function getTokenMinimumNetWorth(address _tokenAddress) public view returns (uint64) {
        return tokenData[_tokenAddress].minimumNetWorth;
    }

    /**
    * @notice get token rules data
    *
    * @param _tokenAddress Address for the Token
    * @return minimum salary required to buy this token
    */
    function getTokenMinimumSalary(address _tokenAddress) public view returns (uint32) {
        return tokenData[_tokenAddress].minimumSalary;
    }

    /**
    * @notice get token rules data
    *
    * @param _tokenAddress Address for the Token
    * @return is accredited investor status required to buy this token?
    */
    function getTokenInvestorStatusRequired(address _tokenAddress) public view returns (bool) {
        return tokenData[_tokenAddress].accreditedInvestorStatusRequired;
    }


    // country ban functions

    /**
    * @notice ban a country for participation
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
    * @notice get token rules data
    *
    * @param _tokenAddress Address for the Token
    * @param _isoCountryCode Country to find out status
    *
    * @return country status
    */
    function getCountryBan(
        address _tokenAddress,
        bytes32 _isoCountryCode)
        public view returns (bool) {
        return bannedCountries[_tokenAddress][_isoCountryCode];
    }

    /**
    * @notice lift a country ban for participation
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


    // functions for buyer's registry - user data

    /**
    * @notice Add a new buyer
    * @dev    This method is only callable by the contract's owner
    *
    * @param _buyerEIN EIN for the buyer
    * @param _firstName First name of the buyer
    * @param _lastName Last name of the buyer
    * @param _isoCountryCode ISO country code for the buyer
    * @param _yearOfBirth Year of birth of the buyer
    * @param _monthOfBirth Month of birth of the buyer
    * @param _dayOfBirth Day of birth of the buyer
    * @param _netWorth Net worth declared by the buyer
    * @param _salary Salary declared by the buyer
    */
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
    //public onlySnowflakeOwner {
    public {
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
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _firstName First name of the buyer
    */
    function getBuyerFirstName(uint _buyerEIN) public view returns (string memory) {
        return buyerRegistry[_buyerEIN].firstName;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _lastName Last name of the buyer
    */
    function getBuyerLastName(uint _buyerEIN) public view returns (string memory) {
        return buyerRegistry[_buyerEIN].lastName;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _isoCountryCode ISO country code for the buyer
    */
    function getBuyerIsoCountryCode(uint _buyerEIN) public view returns (bytes32) {
        return buyerRegistry[_buyerEIN].isoCountryCode;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return birthTimestamp Timestamp for birthday of the buyer
    */
    function getBuyerBirthTimestamp(uint _buyerEIN) public view returns (uint) {
        return buyerRegistry[_buyerEIN].birthTimestamp;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _netWorth Net worth declared by the buyer
    */
    function getBuyerNetWorth(uint _buyerEIN) public view returns (uint64) {
        return buyerRegistry[_buyerEIN].netWorth;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _salary Salary declared by the buyer
    */
    function getBuyerSalary(uint _buyerEIN) public view returns (uint32) {
        return buyerRegistry[_buyerEIN].salary;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _accreditedInvestorStatus Investor status for the buyer
    */
    function getBuyerInvestorStatus(uint _buyerEIN) public view returns (bool) {
        return buyerRegistry[_buyerEIN].accreditedInvestorStatus;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _kycWhitelisted KYC status for the buyer
    */
    function getBuyerKycStatus(uint _buyerEIN) public view returns (bool) {
        return buyerRegistry[_buyerEIN].kycWhitelisted;
    }

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _amlWhitelisted KYC status for the buyer
    */
    function getBuyerAmlStatus(uint _buyerEIN) public view returns (bool) {
        return buyerRegistry[_buyerEIN].amlWhitelisted;
    }

        bool    amlWhitelisted;

    /**
    * @notice get buyer data
    *
    * @param _buyerEIN EIN for the buyer
    * @return _cftWhitelisted KYC status for the buyer
    */
    function getBuyerCftStatus(uint _buyerEIN) public view returns (bool) {
        return buyerRegistry[_buyerEIN].cftWhitelisted;
    }


    // functions for buyer's registry - manage services for a buyer
    // TO DO - only registered providers can modify this data

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
        require (registeredToken() == true, "Token must be registered in Token Registry");
        require (registeredProvider() == true, "Caller must be a registered provider in Service Registry");
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


    // functions to enforce investor rules

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
