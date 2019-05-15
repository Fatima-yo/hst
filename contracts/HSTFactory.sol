pragma solidity ^0.5.0;

import './HSToken.sol';
import './components/SnowflakeOwnable.sol';
import './interfaces/IdentityRegistryInterface.sol';

// TO DO

// check if token exists, then check if it is active
// allow new deployment if any of both is false, if both are true reject deployment

// add mainnet addresses
// add a parameter to choose deployment network

/**
 * @title HSTFactory
 * @notice Perform deployment of contracts for the issuance of Hydro Securities
 * @author Fatima Castiglione Maldonado <castiglionemaldonado@gmail.com>
 */
contract HSTFactory is SnowflakeOwnable {

 /*************************************************
 * Hydro and other addresses on Rinkeby blockchain
 **************************************************/

    // DateTime contract Rinkeby
    //address public dateTimeRinkeby = 0x92482Ba45A4D2186DafB486b322C6d0B88410FE7;

    // IdentityRegistry contract Rinkeby
    //address public identityRinkeby = 0xa7ba71305bE9b2DFEad947dc0E5730BA2ABd28EA;

    // Snowflake contract Rinkeby
    //address public snowflakeRinkeby = 0xB0D5a36733886a4c5597849a05B315626aF5222E;

    // Hydro Token contract Rinkeby, 18 decimals, symbol = HYDRO
    //address public hydroTokenRinkeby = 0x4959c7f62051D6b2ed6EaeD3AAeE1F961B145F20;

    // name of the token => address of the token

    struct Token {
      uint256 id;
      address tokenAddress;
      uint256 owner;
      bool exist;
    }

    uint256 public last_id = 0;

    mapping(bytes32 => Token) tokens;


 /*******************************************************
 * Hydro and other addresses that will be used to deploy
 *******************************************************/

    address dateTimeAddress;
    address identityRegistryAddress;
    address hydroTokenAddress;

    IdentityRegistryInterface IdentityRegistry;

    constructor(address _dateTimeAddress, address _identityRegistryAddress, address _hydroTokenAddress) public {
      dateTimeAddress = _dateTimeAddress;
      identityRegistryAddress = _identityRegistryAddress;
      hydroTokenAddress = _hydroTokenAddress;
      IdentityRegistry = IdentityRegistryInterface(_identityRegistryAddress);
    }

   /**
    * @notice Get a Hydro Securities token contract deployed address
    * @param  _tokenName The name of the token contract set to be deployed
    * @return the address of the token contract corresponding to that name
    */
    function getSecuritiesTokenAddress(bytes32 _tokenName) public view returns(address) {
      return tokens[_tokenName].tokenAddress;
    }

    /**
    * @notice Triggered when a whole set of contracts for a hydro securities token deploy is started
    */
    event SecuritiesDeployStarted(bytes32 _tokenName);

    /**
    * @notice Triggered when a whole set of contracts for a hydro securities token deploy is cancelled
    */
    event SecuritiesDeployCancelled(bytes32 _tokenName, string _reason);

    /**
    * @notice Triggered when a whole set of contracts for a hydro securities token deploy is finished
    */
    event SecuritiesDeployFinished(bytes32 _tokenName);

    /**
    * @notice Triggered when each contract is deployed
    */
    event ContractDeployed(bytes32 indexed _name, bytes32 _type, address indexed _addr);

    /**
    * @notice Deploy a Hydro Securities Token contract set
    * @param  _tokenName The name of the token contract set to be deployed
    */
    function deploySecuritiesTokenContractSet(
      bytes32 _tokenName,
      string memory _description,
      string memory _symbol,
      uint8 _decimals)
    public payable returns(bool) {

      emit SecuritiesDeployStarted(_tokenName);

      if ( tokens[_tokenName].exist ) {
        HSToken _token = HSToken(tokens[_tokenName].tokenAddress);
        if ( _token.isAlive() ) {
          emit SecuritiesDeployCancelled(_tokenName, "Token exists and it is alive");
          return false;
        }
      }

      _deployToken(_tokenName, _description, _symbol, _decimals);
      emit SecuritiesDeployFinished(_tokenName);
      return true;
    }

    /**
    * @notice Deploy a Hydro Securities Token contract
    * @param  _tokenName The name of the token contract set to be deployed
    */
    function _deployToken(
      bytes32 _tokenName,
      string memory _description,
      string memory _symbol,
      uint8 _decimals)
    private {

      last_id++; // Prepare unique id

      HSToken _token = new HSToken(
        last_id,
        _tokenName,
        _description,
        _symbol,
        _decimals,
        hydroTokenAddress,
        identityRegistryAddress,
        msg.sender);

      address _tokenAddress = address(_token);

      tokens[_tokenName].id = last_id;
      tokens[_tokenName].tokenAddress = _tokenAddress;
      tokens[_tokenName].owner = IdentityRegistry.getEIN(msg.sender);
      tokens[_tokenName].exist = true;

      emit ContractDeployed(_tokenName, "HSTOKEN", _tokenAddress);
    }

}
