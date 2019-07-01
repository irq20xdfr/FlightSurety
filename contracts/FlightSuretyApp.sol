pragma solidity ^0.4.25;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    //Reference to data contract
    FlightSuretyData flightSuretyData;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner;          // Account used to deploy contract

    // Contract control flag
    bool public operational;

    //holds votes
    mapping(address => address[]) internal votes;

    //min funding
    uint public minFund = 10 ether;


    /********************************************************************************************/
    /*                                       EVENTS                                             */
    /********************************************************************************************/
    event FlightRegistered(string flight, string to, uint landing);
    event WithdrawRequest(address recipient);
    event FlightProcessed(string flight, string destination, uint timestamp, uint8 statusCode);
    // event that notifies when airline is added specifying airline added and requesting airline
    event AirlineRegistered(address airlineAddr, address requestingAirline);
 
    event Prueba();

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
         // Modify to call data contract's status
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

    // prevents gas wasting by avoiding changing status when the contract is already in that state
    modifier checkPreviousStatus(bool status) {
        require(status != operational, "Contract is already in that state");
        _;
    }

    //checks if airline is already registered
    modifier airlineRegistered() {
        require(flightSuretyData.isRegistered(msg.sender),"Airline is not registered yet");
        _;
    }

    // Checks that enough fund is sent
    modifier enoughFund() {
        require(msg.value >= minFund, "Minimun fund to participate is 10 ETH");
        _;
    }

    // Checks airline has provided funds
    modifier airlineFunded() {
        require(flightSuretyData.hasFunded(msg.sender),"Airline has not provided any funding and it is necessary for this operation");
        _;
    }

    // Checks value is within range
    modifier checkRange(uint value, uint min, uint max) {
        require(value < max, "Value must be lower than maximum allowed");
        require(value > min, "Value must me greater than minimum allowed");
        _;
    }

    // Checks if user paid right amount
    modifier checkPaidEnough(uint _price) {
        require(msg.value >= _price, "Value sent does not cover the price!");
        _;
    }

    // Returns change
    modifier checkValue(uint _price) {
        uint amountToReturn = msg.value - _price;
        msg.sender.transfer(amountToReturn);
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor(address dataContract) public
    {
        operational = true;
        contractOwner = msg.sender;
        flightSuretyData = FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function setOperatingStatus (bool mode) external requireContractOwner
    checkPreviousStatus(mode)
    {
        operational = mode;
    }

    function votesLeft(address airline)
    public
    view
    returns (uint remVotes)
    {
        uint currentVotes = votes[airline].length;
        uint half = flightSuretyData.registeredAirlinesCount().div(2);
        remVotes = half.sub(currentVotes);
    }

    function airlinesCount()
    external
    view
    returns (uint count)
    {
        count = flightSuretyData.registeredAirlinesCount();
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

  
   /**
    * @dev Add an airline to the registration queue
    *
    */
    function registerAirline(address airlineAddress)
    external
    requireIsOperational
    airlineRegistered
    airlineFunded
    returns(bool success, uint256 votesRet)
    {
        if (flightSuretyData.registeredAirlinesCount() < 5) {
            require(flightSuretyData.initialAirline() == msg.sender,"Only 4 or less registered, only the first airline can register more");
            flightSuretyData.registerAirline(airlineAddress, msg.sender);
            emit AirlineRegistered(airlineAddress, msg.sender);
        } else {
            // process to validate multi party consensus
            bool isDuplicate = false;
            for (uint i = 0; i < votes[airlineAddress].length; i++) {
                if (votes[airlineAddress][i] == msg.sender) {
                    isDuplicate = true;
                    break;
                }
            }
            require(!isDuplicate, "This airline already voted");
            votes[airlineAddress].push(msg.sender);

            if (votesLeft(airlineAddress) == 0) {
                votes[airlineAddress] = new address[](0);
                flightSuretyData.registerAirline(airlineAddress, msg.sender);
                emit AirlineRegistered(airlineAddress, msg.sender);
                success = true;
            }
        }
        votesRet = votes[airlineAddress].length;
        return (success, votesRet);
    }

    function fund()
    external
    airlineRegistered
    enoughFund
    requireIsOperational
    payable
    {
        flightSuretyData.fund.value(msg.value)(msg.sender);
    }


   /**
    * @dev Register a future flight for insuring.
    *
    */
    function registerFlight
    (
        uint takeOff,
        uint landing,
        string flight,
        uint price,
        string from,
        string to
    )
    external
    requireIsOperational
    airlineFunded
    {
        flightSuretyData.registerFlight(
            takeOff,
            landing,
            flight,
            price,
            from,
            to,
            msg.sender
        );
        emit FlightRegistered(flight, to, landing);
    }


    function buy
    (
        string _flight,
        string _to,
        uint _landing,
        uint amount
    )
    external
    checkRange(amount, 0, 1.1 ether) // Check amount paid covers 1 ether
    checkPaidEnough(flightSuretyData.getFlightPrice(getFlightKey(_flight, _to, _landing)).add(amount))
    checkValue(flightSuretyData.getFlightPrice(getFlightKey(_flight, _to, _landing)).add(amount))
    requireIsOperational
    payable
    {
        bytes32 flightKey = getFlightKey(_flight, _to, _landing);
        flightSuretyData.buy.value(msg.value)(flightKey, amount, msg.sender);
    }

    function withdraw()
    external
    requireIsOperational
    {
        flightSuretyData.pay(msg.sender);
        emit WithdrawRequest(msg.sender);
    }


   /**
    * @dev Called after oracle has updated flight status
    *
    */
    function processFlightStatus
    (
        string flight,
        string destination,
        uint256 timestamp,
        uint8 statusCode
    )
    internal
    requireIsOperational
    {
        emit Prueba();
        // generate flightKey
        bytes32 flightKey = getFlightKey(flight, destination, timestamp);
        flightSuretyData.processFlightStatus(flightKey, statusCode);

        emit FlightProcessed(flight, destination, timestamp, statusCode);
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus
    (
        string flight,
        string destination,
        uint256 timestamp
    )
    external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = getFlightKey(flight, destination, timestamp);
        oracleResponses[key] = ResponseInfo({
            requester: msg.sender,
            isOpen: true
        });

        emit OracleRequest(index, flight, destination, timestamp);
    }


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 4;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;        
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    event OracleRegistered(uint8[3] indexes);

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(string flight, string destination, uint256 timestamp, uint8 status);

    event OracleReport(string flight, string destination, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, string flight, string destination, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle
                            (
                            )
                            external
                            payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
                                        isRegistered: true,
                                        indexes: indexes
                                    });
        emit OracleRegistered(indexes);
    }

    function getMyIndexes
                            (
                            )
                            view
                            external
                            returns(uint8[3])
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
                        (
                            uint8 index,
                            string flight,
                            string destination,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
    {
        emit Prueba();
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index)
        || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = getFlightKey(flight, destination, timestamp);
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);
        //emit OracleReport(flight, destination, timestamp, statusCode);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(flight, destination, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length == MIN_RESPONSES) {
            oracleResponses[key].isOpen = false;
            emit FlightStatusInfo(flight, destination, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(flight, destination, timestamp, statusCode);
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

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes
                            (                       
                                address account         
                            )
                            internal
                            returns(uint8[3])
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex
                            (
                                address account
                            )
                            internal
                            returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }
// endregion
}


// FlightSuretyData interface
contract FlightSuretyData {

    function registerAirline(address airlineAddress, address originAddress) external;
    function fund(address originAddress) external payable;

    function registerFlight
    (
        uint takeOff,
        uint landing,
        string flight,
        uint price,
        string from,
        string to,
        address originAddress
    )
    external;

    function book(bytes32 flightKey, uint amount, address originAddress) external payable;
    function pay(address originAddress) external;
    function buy(bytes32 flightKey, uint amount, address originAddress) external payable;
    function processFlightStatus(bytes32 flightKey, uint8 status)  external;
    function getFlightPrice(bytes32 flightKey) external view returns (uint);
    function hasFunded(address airlineAddress) external view returns (bool);
    function isRegistered(address airlineAddress) external view returns (bool);
    function registeredAirlinesCount() external view returns (uint);
    function initialAirline() external view returns (address);


}
