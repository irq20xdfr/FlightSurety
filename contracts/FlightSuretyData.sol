pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

   struct Airline {
        bool registered;
        bool funded;
    }

    // Flight structure
    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 takeOff;
        uint256 landing;
        address airline;
        string flightNo;
        uint price;
        string from;
        string to;
        mapping(address => bool) bookings;
        mapping(address => uint) insurances;

    }

    address[] internal passengers;

    mapping(bytes32 => Flight) public flights;
    bytes32[] public flightKeys;
    uint public indexFlightKeys = 0;

    address private contractOwner;                                      // Account used to deploy contract
    mapping(address => bool) public authorizedCallers;                  // Array to hold authorized callers
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    mapping(address => Airline) public airlines;                        // Airlines array
    uint public registeredAirlinesCount;                                // Keeps a count of the registered airlines
    address public initialAirline;                                      // Initial airline
    mapping(address => uint) public withdrawals2;                       // Keeps track of withdrawals

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/
    event Paid(address recipient, uint amount);
    event Funded(address airline);
    event AirlineRegistered(address origin, address airline);
    event Credited(address passenger, uint amount);
    event FlightBought(address passenger, string flightNo);
    event CreditingInsurees();

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor(address _initialAirline) public
    {
        contractOwner = msg.sender;
        initialAirline = _initialAirline;
        registeredAirlinesCount = 1;
        airlines[_initialAirline].registered = true;

    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational()
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    //Check if caller is authorized
    modifier callerAuthorized() {
        require(authorizedCallers[msg.sender] == true, "Address not authorized to call this function");
        _;
    }

    // prevents gas wasting by avoiding changing status when the contract is already in that state
    modifier checkPreviousStatus(bool status) {
        require(status != operational, "Contract is already in that state");
        _;
    }

    //Check if flight is registered
    modifier isFlightRegistered(bytes32 flightKey) {
        require(flights[flightKey].isRegistered, "This flight is not registered");
        _;
    }

    //Checks flight is not already processed
    modifier isNotProcessed(bytes32 flightKey) {
        require(flights[flightKey].statusCode == 0, "This flight has already been processed");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational()
    public
    view
    returns(bool)
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus
    (bool mode)
    external
    requireContractOwner
    checkPreviousStatus(mode)
    {
        operational = mode;
    }

    function authorizeCaller(address callerAddress)
    external
    requireContractOwner
    requireIsOperational
    {
        authorizedCallers[callerAddress] = true;
    }

    function hasFunded(address airlineAddress)
    external
    view
    returns (bool _hasFunded)
    {
        _hasFunded = airlines[airlineAddress].funded;
    }

    function isRegistered(address airlineAddress)
    external
    view
    returns (bool _registered)
    {
        _registered = airlines[airlineAddress].registered;
    }

    function getFlightPrice(bytes32 flightKey)
    external
    view
    returns (uint price)
    {
        price = flights[flightKey].price;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerAirline
                            (
                            address airlineAddress,
                            address originAddress
                            )
                            external
                            requireIsOperational
                            callerAuthorized
    {
        registeredAirlinesCount++;
        airlines[airlineAddress].registered = true;
        emit AirlineRegistered(originAddress, airlineAddress);
    }

    /**
        Registers a new flight
     */
    function registerFlight
    (
        uint _takeOff,
        uint _landing,
        string _flight,
        uint _price,
        string _from,
        string _to,
        address originAddress
    )
    external
    requireIsOperational
    callerAuthorized
    {
        require(_takeOff > now, "Take off time must be in the future");
        require(_landing > _takeOff, "Landing time must be greater than take off time");

        Flight memory flight = Flight(
            true,
            0,
            _takeOff,
            _landing,
            originAddress,
            _flight,
            _price,
            _from,
            _to
        );
        bytes32 flightKey = getFlightKey(_flight, _to, _landing);
        flights[flightKey] = flight;
        indexFlightKeys = flightKeys.push(flightKey).sub(1);
    }


   /**
    * @dev Buy insurance for a flight
    *
    */
    function buy(bytes32 flightKey, uint amount, address originAddress)
    external
    requireIsOperational
    callerAuthorized
    isFlightRegistered(flightKey)
    payable
    {
        Flight storage flightToBuy = flights[flightKey];
        flightToBuy.bookings[originAddress] = true;
        flightToBuy.insurances[originAddress] = amount;
        passengers.push(originAddress);
        withdrawals2[flightToBuy.airline] = flightToBuy.price;
        emit FlightBought(originAddress, flightToBuy.flightNo);
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees(bytes32 flightKey)
    public
    requireIsOperational
    isFlightRegistered(flightKey)
    {
        Flight storage flight = flights[flightKey];
        // pay all passengers insurance amount
        for (uint i = 0; i < passengers.length; i++) {
            // Since we cannot save decimal numbers in solidity we have to multiply and divide numerator and denominator
            withdrawals2[passengers[i]] = flight.insurances[passengers[i]].mul(3).div(2);
            emit Credited(passengers[i], flight.insurances[passengers[i]]);
        }
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address originAddress)
    external
    requireIsOperational
    callerAuthorized
    {
        // We use the Check-Effect-Interaction pattern
        // Check
        require(withdrawals2[originAddress] > 0, "Currently there is no amount to be transferred");
        // Effect
        uint amount = withdrawals2[originAddress];
        withdrawals2[originAddress] = 0;
        // Interaction
        originAddress.transfer(amount);
        emit Paid(originAddress, amount);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fund(address originAddress)
    public
    requireIsOperational
    callerAuthorized
    payable
    {
        airlines[originAddress].funded = true;
        emit Funded(originAddress);
    }

    
    // Function to process flight status and in case it is delayed it credits de insurees
    function processFlightStatus(bytes32 flightKey, uint8 statusCode)
    external
    isFlightRegistered(flightKey)
    requireIsOperational
    callerAuthorized
    isNotProcessed(flightKey)
    {
        // Check
        Flight storage flight = flights[flightKey];
        // Effect
        flight.statusCode = statusCode;
        // Interact
        // In case the delay is caused by the airline
        if (statusCode == 20) {
            emit CreditingInsurees();
            creditInsurees(flightKey);
        }
    }

    function getFlightKey
    (
        string memory flight,
        string memory to,
        uint timestamp
    )
    internal
    pure
    returns(bytes32)
    {
        return keccak256(abi.encodePacked(flight, to, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() external callerAuthorized payable
    {
        require(msg.data.length == 0, "The message didn't contain data");
        fund(msg.sender);
    }


}

