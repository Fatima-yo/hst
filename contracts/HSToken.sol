pragma solidity ^0.5.0;

import './interfaces/HSTBuyerRegistryInterface.sol';
import './interfaces/HydroInterface.sol';
import './interfaces/IdentityRegistryInterfaceShort.sol';
import './zeppelin/math/SafeMath.sol';
import './modules/PaymentSystem.sol';

// Rinkeby testnet addresses
// HydroToken: 0x4959c7f62051d6b2ed6eaed3aaee1f961b145f20
// IdentityRegistry: 0xa7ba71305be9b2dfead947dc0e5730ba2abd28ea

/**
 * @title HSToken
 * @notice The Hydro Security Token is part of the Hydro Security Tokens Framework,
 * a system to allow organizations to create their own Security Tokens,
 * related to their Snowflake identities, serviced by external KYC, AML and CFT services,
 * and restrainable by some rules.
 * @author Juan Livingston <juanlivingston@gmail.com>
 */

interface Raindrop {
    function authenticate(address _sender, uint _value, uint _challenge, uint _partnerId) external;
}

interface tokenRecipient {
    function receiveApproval(address _from, uint256 _value, address _token, bytes calldata _extraData) external;
}

/**
* @dev We use contracts to store main variables, because Solidity can not handle so many individual variables
*/

contract MAIN_PARAMS {
    bool public MAIN_PARAMS_ready;

    uint256 public hydroPrice;
    uint256 public lockEnds; // Ending date of locking period
    uint256 public maxSupply;
    uint256 public escrowLimitPeriod;
}

contract STO_FLAGS {
    bool public STO_FLAGS_ready;

    bool public LIMITED_OWNERSHIP;
    bool public PERIOD_LOCKED;  // Locked period active or inactive
    bool public PERC_OWNERSHIP_TYPE; // is percentage of ownership limited?
    bool public HYDRO_AMOUNT_TYPE; // is Hydro amount limited?
    bool public WHITELIST_RESTRICTED;
    bool public BLACKLIST_RESTRICTED;
}

contract STO_PARAMS {
    bool public STO_PARAMS_ready;
    // @param percAllowedTokens: 100% = 1 ether, 50% = 0.5 ether
    uint256 public percAllowedTokens; // considered if PERC_OWNERSHIP_TYPE
    uint256 public hydroAllowed; // considered if HYDRO_AMOUNT_TYPE
    uint256 public lockPeriod; // in days
    uint256 public minInvestors;
    uint256 public maxInvestors;
    address public hydroOracle;
}

contract STO_Interests {
    uint256 public marketStarted; // Date for market stage
    uint256[] internal periods;
}

contract HSToken is MAIN_PARAMS, STO_FLAGS, STO_PARAMS, STO_Interests, PaymentSystem {

    using SafeMath for uint256;

    enum Stage {
        SETUP, PRELAUNCH, PRESALE, SALE, LOCK, MARKET, FINALIZED
    }

    // Lock state
    bool public locked; // Mark if token transfers are locked

	// Main parameters
    uint256 public registrationDate; // Token creation and registration date

	uint256 public id; // Unique HSToken id
	bytes32 public name;
	string public description;
	bytes32 public symbol;
    uint8 public decimals;
    address payable public Owner;
    uint256 public einOwner;
    address public createdBy;

    // State Memory
    Stage public stage; // SETUP, PRELAUNCH, PRESALE, SALE, LOCK, MARKET, FINALIZED

    // uint256 public issuedTokens; // Moved to payment module
    uint256 public hydroReceived;
    uint256 public numberOfInvestors;
    uint256 public hydrosReleased; // Number of Hydros released by owner

    address public raindropAddress;

    // address InterestSolver;

    // Mappings
    mapping(uint256 => bool) public whitelist;
    mapping(uint256 => bool) public blacklist;
    mapping(uint256 => bool) public freezed;
    mapping(address => mapping(address => uint256)) public allowed;
    mapping(uint256 => Investor) public investors;

    // Balances
    mapping(address => uint256) public balance;
    // This was moved to the payment module
    // mapping(uint256 => mapping(address => uint256)) public balanceAt;

    // Declaring interfaces
    IdentityRegistryInterface public IdentityRegistry;
    HydroInterface public HydroToken;
    HSTBuyerRegistryInterface public BuyerRegistry;

    event HydroSTCreated(
        uint256 indexed id,
        bytes32 name,
        bytes32 symbol,
        uint8 decimals,
        uint256 einOwner
        );

    event PaymentPeriodBoundariesAdded(
    	uint256[] _periods
    	);

    event Sell(address indexed _owner, uint256 _amount);

    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _amount
    );

    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _amount
    );

/**
* @dev Most repeated modifiers are replaced by functions to optimize bytecode at deployment
*/

/*    modifier isUnlocked() {
        require(!locked, "Token locked");
        if (PERIOD_LOCKED) require (block.timestamp > lockEnds, "Locked period active");
        _;
    }

    modifier isUnfreezed(address _from, address _to) {
        require(!freezed[IdentityRegistry.getEIN(_to)], "Target EIN is freezed");
        require(!freezed[IdentityRegistry.getEIN(_from)], "Source EIN is freezed");
        _;
    }

    modifier onlyAtSetup() {
        require(stage == Stage.SETUP && (block.timestamp - registrationDate) < (15 * 24 * 60 * 60), "This is not setup stage");
        _;
    }

    modifier onlyAdmin() {
        // Check if EIN of sender is the same as einOwner
        require(IdentityRegistry.getEIN(msg.sender) == einOwner, "Only for admins");
        _;
    }
*/

    modifier onlyActive() {
        require(
            stage == Stage.PRESALE ||
            stage == Stage.SALE ||
            stage == Stage.MARKET,
            "Not in active stage"
            );
        _;
    }

    modifier escrowReleased() {
        require(escrowLimitPeriod < block.timestamp, "Escrow limit period is still active");
        require(BuyerRegistry.getTokenLegalStatus(address(this)), "Legal conditions are not met");
        _;
    }

    constructor(
        uint256 _id,
        uint8 _stoType,
        bytes32 _name,
        string memory _description,
        bytes32 _symbol,
        uint8 _decimals,
        address _hydroToken,
        address _identityRegistry,
        address _buyerRegistry,
        address payable _owner
    ) public {
        id = _id;
        name = _name;
        description = _description;
        symbol = _symbol;
        decimals = _decimals;

        setSTOType(_stoType);

        registrationDate = block.timestamp;
        // locked = true;

        // State Memory
        stage = Stage.SETUP;

        periods.push(block.timestamp);

        // Links to Modules
        HydroToken = HydroInterface(_hydroToken);
        // 0x4959c7f62051D6b2ed6EaeD3AAeE1F961B145F20
        IdentityRegistry = IdentityRegistryInterface(_identityRegistry);
        // 0xa7ba71305bE9b2DFEad947dc0E5730BA2ABd28EA
        BuyerRegistry = HSTBuyerRegistryInterface(_buyerRegistry);
        // raindropAddress = _RaindropAddress;

        Owner = _owner;
        einOwner = IdentityRegistry.getEIN(Owner);
        createdBy = msg.sender;

        emit HydroSTCreated(id, name, symbol, decimals, einOwner);
    }


    // ADMIN SETUP FUNCTIONS


    function set_MAIN_PARAMS(
        uint256 _hydroPrice,
        uint256 _lockEnds,
        uint256 _maxSupply,
        uint256 _escrowLimitPeriod
    )
        public 
    {
        onlyAdmin();
        checkSetup();

        // Validations
        require(
            _hydroPrice > 0 &&
            _lockEnds > block.timestamp &&
            _maxSupply > 10000 &&
            _escrowLimitPeriod > (10 * 24 * 60 * 60),
            "Incorrect input data"
        );
        require(!MAIN_PARAMS_ready, "Params already setted");
        // Load values
        hydroPrice = _hydroPrice;
        lockEnds = _lockEnds; // Date of end of locking period
        maxSupply = _maxSupply;
        escrowLimitPeriod = _escrowLimitPeriod;
        // Set flag
        MAIN_PARAMS_ready = true;
    }

    function set_STO_FLAGS(
        bool _LIMITED_OWNERSHIP,
        bool _PERIOD_LOCKED,
        bool _PERC_OWNERSHIP_TYPE,
        bool _HYDRO_AMOUNT_TYPE,
        bool _WHITELIST_RESTRICTED,
        bool _BLACKLIST_RESTRICTED
    )
        public 
    {
        onlyAdmin();
        checkSetup();
        require(!STO_FLAGS_ready, "Flags already setted");
        // Load values
        LIMITED_OWNERSHIP = _LIMITED_OWNERSHIP;
        PERIOD_LOCKED = _PERIOD_LOCKED;
        PERC_OWNERSHIP_TYPE = _PERC_OWNERSHIP_TYPE;
        HYDRO_AMOUNT_TYPE = _HYDRO_AMOUNT_TYPE;
        WHITELIST_RESTRICTED = _WHITELIST_RESTRICTED;
        BLACKLIST_RESTRICTED = _BLACKLIST_RESTRICTED;
        // Set flag
        STO_FLAGS_ready = true;
    }

    function set_STO_PARAMS(
        uint256 _percAllowedTokens,
        uint256 _hydroAllowed,
        uint256 _lockPeriod,
        uint256 _minInvestors,
        uint256 _maxInvestors,
        address _hydroOracle
    )
        public 
    {
        onlyAdmin();
        checkSetup();
        require(!STO_PARAMS_ready, "Params already setted");
        require(STO_FLAGS_ready, "STO_FLAGS has not been set");
        // Load values
        percAllowedTokens = _percAllowedTokens;
        hydroAllowed = _hydroAllowed;
        lockPeriod = _lockPeriod;
        minInvestors = _minInvestors;
        maxInvestors = _maxInvestors;
        hydroOracle = _hydroOracle;
        // Set flag
        STO_PARAMS_ready = true;
    }


    // ADMIN CHANGING STAGES -------------------------------------------------------------------

    function stagePrelaunch()
        public 
    {
        onlyAdmin();
        checkSetup();
        require(MAIN_PARAMS_ready, "MAIN_PARAMS not setted");
        require(STO_FLAGS_ready, "STO_FLAGS not setted");
        require(STO_PARAMS_ready, "STO_PARAMS not setted");
        require(EXT_PARAMS_ready, "EXT_PARAMS not setted"); // Parameters required for payment module
        stage = Stage.PRELAUNCH;
    }

    function stagePresale()
        public 
    {
        onlyAdmin();
    	require(stage == Stage.PRELAUNCH, "Stage should be Prelaunch");
        require(BuyerRegistry.getTokenLegalStatus(address(this)), "Token needs legal approval");
        stage = Stage.PRESALE;
    }

    function stageSale()
        public 
    {
        onlyAdmin();
    	require(stage == Stage.PRESALE, "Stage should be Presale");
        stage = Stage.SALE;
    }

    function stageLock()
        public 
    {
        onlyAdmin();
    	require(stage == Stage.SALE, "Stage should be Sale");
        require(numberOfInvestors >= minInvestors, "Number of investors has not reached the minimum");
        stage = Stage.LOCK;
    }


    function stageMarket()
    	public  
    {
        onlyAdmin();
    	require(stage == Stage.LOCK, "Stage should be Lock");
    	stage = Stage.MARKET;
    	marketStarted = block.timestamp;
    }



    // ADMIN GENERAL FUNCTIONS ----------------------------------------------------------------

    function getTokenEINOwner() public view returns(uint) {
        return einOwner;
    }

    function getTokenOwner() public view returns(address) {
        return Owner;
    }

    function setLockupPeriod(uint256 _lockEnds)
        public 
    {
        onlyAdmin();
        // Remove lock period
        if (_lockEnds == 0) {
            PERIOD_LOCKED = false;
            lockEnds = 0;
            return;
            }
        // Add lock period
        require(_lockEnds > block.timestamp + 24 * 60 * 60, "Lock ending should be at least 24 hours in the future");
        PERIOD_LOCKED = true;
        lockEnds = _lockEnds;
    }


    function changeBuyerRegistry(address _newBuyerRegistry) public  
    {
        onlyAdmin();
    	require(stage == Stage.SETUP, "Stage should be Setup to change this registry");
		BuyerRegistry = HSTBuyerRegistryInterface(_newBuyerRegistry);
    }

    function lock() public  
    {
        onlyAdmin();
        locked = true;
    }

    function unLock() public  
    {
        onlyAdmin();
        locked = false;
    }

    function addWhitelist(uint256[] memory _einList) public  
    {
        onlyAdmin();
        for (uint i = 0; i < _einList.length; i++) {
          whitelist[_einList[i]] = true;
        }
    }

    function addBlacklist(uint256[] memory _einList) public  
    {
        onlyAdmin();
        for (uint i = 0; i < _einList.length; i++) {
          blacklist[_einList[i]] = true;
        }
    }

    function removeWhitelist(uint256[] memory _einList) public  
    {
        onlyAdmin();
        for (uint i = 0; i < _einList.length; i++) {
          whitelist[_einList[i]] = false;
        }

    }

    function removeBlacklist(uint256[] memory _einList) public  
    {
        onlyAdmin();
        for (uint i = 0; i < _einList.length; i++) {
          blacklist[_einList[i]] = false;
        }
    }

    function freeze(uint256[] memory _einList) public  
    {
        onlyAdmin();
        for (uint i = 0; i < _einList.length; i++) {
          freezed[_einList[i]] = true;
        }
    }

    function unFreeze(uint256[] memory _einList) public  
    {
        onlyAdmin();
        for (uint i = 0; i < _einList.length; i++) {
          freezed[_einList[i]] = false;
        }
    }


    function addPaymentPeriodBoundaries(uint256[] memory _periods) public  
    {
        onlyAdmin();
        require(_periods.length > 0, "There should be at least one period set");
        for (uint i = 0; i < _periods.length; i++) {
          require(periods[periods.length-1] < _periods[i], "New periods must be after last period registered");
          periods.push(_periods[i]);
        }
        emit PaymentPeriodBoundariesAdded(_periods);
    }


    function getPaymentPeriodBoundaries() public view returns(uint256[] memory) {
    	return periods;
    }


    function addHydroOracle(address _newAddress) public  
    {
        onlyAdmin();
    	hydroOracle = _newAddress;
    }


    // Release gains Only after escrow is released
    function releaseHydroTokens() public escrowReleased  
    {
        onlyAdmin();
        uint256 thisBalance = HydroToken.balanceOf(address(this));
        require(thisBalance > 0, "There are not HydroTokens in this account");
        hydrosReleased = hydrosReleased + thisBalance;
        require(HydroToken.transfer(Owner, thisBalance), "Error while releasing Tokens");
    }


    // PUBLIC FUNCTIONS FOR INVESTORS -----------------------------------------------------------------


    function buyTokens(uint256 _amount)
        public onlyActive payable
        returns(bool)
    {
        uint256 total;
        uint256 _ein = IdentityRegistry.getEIN(msg.sender);

        if (!investors[_ein].exists) {
            numberOfInvestors++;
            investors[_ein].exists = true;
            require(numberOfInvestors <= maxInvestors || maxInvestors == 0, "Maximum number of investors reached");
        }

        // Check for limits
        if (HYDRO_AMOUNT_TYPE) {
            require(hydroReceived.add(_amount) <= hydroAllowed, "Hydro amount exceeded");
        }

        // Check with KYC and AML providers
        BuyerRegistry.checkRules(_ein);

        // If Stage is PRESALE, check with whitelist and blacklist
        if (stage == Stage.PRESALE) {
            if (WHITELIST_RESTRICTED) _checkWhitelist(_ein);
            if (BLACKLIST_RESTRICTED) _checkBlacklist(_ein);
        }

        // Calculate total
        total = _amount.mul(hydroPrice) / 1 ether;
        // Adjust state
        investors[_ein].hydroSent = investors[_ein].hydroSent.add(_amount);
        hydroReceived = hydroReceived.add(_amount);
        issuedTokens = issuedTokens.add(total);
        balance[msg.sender] = balance[msg.sender].add(total);
        balanceAt[0][msg.sender] = balance[msg.sender];

        // Check with maxSupply
        require(issuedTokens <= maxSupply, "Max supply of Tokens is exceeded");

        // Check for ownership percentage
        if (PERC_OWNERSHIP_TYPE) {
            require ((issuedTokens.mul(1 ether) / maxSupply) < percAllowedTokens,
                "Perc ownership exceeded");
        }

        // Transfer Hydrotokens from buyer to this contract
        require(HydroToken.transferFrom(msg.sender, address(this), _amount),
            "Hydro transfer was not possible");

        emit Sell(msg.sender, total);
        return true;
    }


    // To be accesed by modules ---------------------------------------------------------------

    // FUNCTIONS

    function _transferHydroToken(address _address, uint256 _payment) private returns(bool) {
        return HydroToken.transfer(_address, _payment);
    }

    // GETTERS

    function _getEIN(address _address) private view returns(uint256) {
        return IdentityRegistry.getEIN(_address);
    }

    function _getStage() private view returns(uint256) {
    	return uint(stage);
    }

    function _getTokenEinOwner() private view returns(uint256) {
    	return einOwner;
    }

    function _hydroTokensBalance() private view returns(uint256) {
    	return HydroToken.balanceOf(address(this));
    }


    // Token ERC-20 wrapper ---------------------------------------------------------------------

    function transfer(address _to, uint256 _amount)
        public
        returns(bool success)
    {
        checkMarketStage();
        checkUnfreezed(msg.sender, _to);

        BuyerRegistry.checkRules(IdentityRegistry.getEIN(_to));

        _doTransfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount)
        public
        returns(bool success)
    {
        checkMarketStage();
        checkUnfreezed(_from, _to);

        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);

        BuyerRegistry.checkRules(IdentityRegistry.getEIN(_to));

        _doTransfer(_from, _to, _amount);
        return true;
    }

    function balanceOf(address _from) public view returns(uint256) {
        return balance[_from];
    }

    function approve(address _spender, uint256 _amount) public returns(bool success) {
        // To change the approve amount you first have to reduce the addresses`
        //  allowance to zero by calling `approve(_spender,0)` if it is not
        //  already 0 to mitigate the race condition described here:
        //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require(_amount == 0 || allowed[msg.sender][_spender] == 0, "Approved amount should be zero before changing it");
        allowed[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, address(this), _extraData);
            return true;
        }
    }

    function authenticate(uint _value, uint _challenge, uint _partnerId) public {
        Raindrop raindrop = Raindrop(raindropAddress);
        raindrop.authenticate(msg.sender, _value, _challenge, _partnerId);
        _doTransfer(msg.sender, Owner, _value);
    }


    function _doTransfer(address _from, address _to, uint256 _amount) private {
        uint256 _period = getPeriod();
        balance[_to] = balance[_to].add(_amount);
        balance[_from] = balance[_from].sub(_amount);
        balanceAt[_period][_to] = balance[_to];
        balanceAt[_period][_from] = balance[_from];
        lastBalance[_from] = _period;
        lastBalance[_to] = _period;
        emit Transfer(_from, _to, _amount);
    }

    // PUBLIC GETTERS --------------------------------------------------------------------------

    function isTokenLocked() public view returns(bool) {
        if (locked) return true;
        if (PERIOD_LOCKED && block.timestamp < lockEnds) return true;
        return false;
    }

    function isTokenAlive() public view returns(bool) {
        if (stage != Stage.SETUP) return true;
        if (!tokenInSetupStage()) return false;
        return true;
    }


    function getNow() public view returns(uint256) {
    	return block.timestamp;
    }

    function getPeriod() public view returns(uint256) {
        if (periods.length < 2) return 0;
        for (uint i = 1; i < periods.length; i++) {
          if (periods[i] > block.timestamp) return i-1;
        }
        return periods[periods.length-1];
    }

    // FUNCTIONS TO BE USED EXCLUSIVELY BY ORACLES

    function updateHydroPrice(uint256 _newPrice) external {
    	require(msg.sender == hydroOracle, "Only registered Oracle can set Hydro price");
    	hydroPrice = _newPrice;
    }

    function notifyPeriodProfits(uint256 _profits) public {
        require(msg.sender == hydroOracle, "Only registered oracle can notify profits");
        require(_profits > 0, "Profits has to be greater than zero");
        uint256 _periodToPay = getPeriod();
        require(profits[_periodToPay] == 0, "Period already notified");

        profits[_periodToPay] = _profits;

        if (stoType == STOTypes.UNITS) {
            uint256 _paymentForManager = _profits.mul(carriedInterestRate) / 1 ether;
            require(_transferHydroToken(msg.sender, _paymentForManager), "Error while releasing Tokens");
        }

        emit PeriodNotified(_periodToPay, _profits);
    }

    // PRIVATE FUNCTIONS --------------------------------------------------------------------

    // Used as modifiers to optimize bytecode at deployment

    function onlyAdmin() private view {
        // Check if EIN of sender is the same as einOwner
        require(IdentityRegistry.getEIN(msg.sender) == einOwner, "Only for admins");
    }

    function checkSetup() private view { // replaces onlyAtSetup() modifier
        require(stage == Stage.SETUP && (block.timestamp - registrationDate) < (15 * 24 * 60 * 60), "This is not setup stage");
    }

    function checkMarketStage() private view {
        require(stage == Stage.MARKET, "Token is not in market stage yet");
        require(!locked, "Token locked");
        if (PERIOD_LOCKED) require (block.timestamp > lockEnds, "Locked period active");
    }

    function checkUnfreezed(address _from, address _to) private view {
        require(!freezed[IdentityRegistry.getEIN(_to)], "Target EIN is freezed");
        require(!freezed[IdentityRegistry.getEIN(_from)], "Source EIN is freezed");
    }


    // Other private functions

    function setSTOType(uint8 _stoType) private {
        require(_stoType < 3, "STO Type not recognized. 0: Shares, 1: Units, 3: Bonds");
        stoType = STOTypes(_stoType);
    }

    function tokenInSetupStage() private view returns(bool) {
        // Stage is SETUP and 15 days to complete setup has not passed yet
        return(stage == Stage.SETUP && (block.timestamp - registrationDate) < (15 * 24 * 60 * 60));
    }

    function _checkWhitelist(uint256 _einUser) private view {
        require(whitelist[_einUser], "EIN address not in whitelist");
    }

    function _checkBlacklist(uint256 _einUser) private view {
        require(!blacklist[_einUser], "EIN address is blacklisted");
    }


}
