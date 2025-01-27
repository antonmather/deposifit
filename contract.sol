pragma solidity ^0.7.0;
// SPDX-License-Identifier: MIT

import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";
//import "@chainlink/contracts/src/v0.7/vendor/SafeMathChainlink.sol";
// what is SafeMathChainklink.sol?
import "@chainlink/contracts/src/v0.7/KeeperCompatible.sol";

contract pledge is KeeperCompatibleInterface {
    //using SafeMathChainlink for uint256; // I don't know why but it sounds nice 

    uint256 private immutable steps_target;
    uint256 private immutable date_target;
    address payable immutable private success_destination;
    
    // Constants
    uint256 public constant MINIMUM_PLEDGE = 50 * 10 ** 18; //require at least 50 usd in stupid units
    uint8 public constant MAX_DONORS = 20; // max number of donors so dont risk gas getting too expensive
    uint256 public constant SECONDS_IN_DAY = 86400;

    //address rinkby_eth_usd = 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e;
    address constant kovan_eth_usd = 0x9326BFA02ADD2366b30bacB125260Af641031331;
    
    uint8 public donors_so_far = 0;
    bool public date_reached=false;
    bool public steps_reached=false;

    //Deposit[] deposits;
    
    // a new type to contain all relevant info about a depoit to the contract
    struct Deposit {
        uint256 amount;
        address payable fail_destination;
    }
    
    mapping (address=>Deposit) public address_to_deposit;
    address[] public userAddresses; // this is needed to iterate the mapping. mappings alone cannot be iterated
    

    //Not sure if/why we need this
    function getVersion() public view returns (uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(kovan_eth_usd); 
        return priceFeed.version();
    }
    
    function getPrice() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(kovan_eth_usd);
        (,int256 answer,,,) = priceFeed.latestRoundData();
         return uint256(answer * 10000000000);
    }
    
    // this converts however much eth they spend to usd
    function convertToUSD(uint256 ethAmount) public view returns (uint256){
        uint256 ethPrice = getPrice();
        uint256 ethAmountInUsd = (ethPrice * ethAmount) / 1000000000000000000;
        return ethAmountInUsd;
    }
    
    //// These query functions will not be 'view' they will require transactions to the oracles
    function query_date() public view returns(uint256){
        //date could be obtained from oracle here but for now timestamp is good enough
        return block.timestamp;
    }
    function query_steps() public view returns(uint256){
        //steps from fitbit API here
        return 100000;
    }
    
    // error due to including "public" in constructor: https://ethereum.stackexchange.com/questions/98453/visibility-for-constructor-is-ignored-if-you-want-the-contract-to-be-non-deploy/101614
    
    constructor(uint256 _steps_target, uint256 _num_days, address payable _success_destination, address payable _fail_destination) public payable {
        //owner = msg.sender; // What does this do?
        
        // Validate data
        require(_steps_target > 100,"have some ambition");
        require(_num_days >= 30, "goal must be at least 30 days away" ); // Could query todays date here if it were worth the money to bother
        uint256 valueInUSD = convertToUSD(msg.value);
        require(valueInUSD >= MINIMUM_PLEDGE, "You need to spend more ETH!");

        // Set success data
        steps_target = _steps_target;
        date_target = block.timestamp + (_num_days * SECONDS_IN_DAY);
        success_destination = _success_destination;
        
        // code below same as fund() - see there for comments
        
        Deposit memory initial_deposit = Deposit({amount:msg.value, fail_destination:_fail_destination});
        address_to_deposit[msg.sender] = initial_deposit;
        userAddresses.push(msg.sender); 
        //deposits.push(initial_deposit);

        //address_to_deposit[msg.sender].amount += msg.value; 
        //address_to_deposit[msg.sender].success_destination = _success_destination;
        //address_to_deposit[msg.sender].fail_destination = _fail_destination;
        
    }
    
    
    function fund(address payable _fail_destination) external payable{
        require(donors_so_far < MAX_DONORS, "sorry this contract is full");
        uint256 valueInUSD = convertToUSD(msg.value);
        require(valueInUSD >= MINIMUM_PLEDGE, "comeon, be generous");

        
        
        if (address_to_deposit[msg.sender].amount==0){ // this person hasn't previously submitted -- min deposit ensures this
            Deposit memory new_deposit = Deposit({amount:msg.value, fail_destination:_fail_destination});
            address_to_deposit[msg.sender] = new_deposit;
            userAddresses.push(msg.sender);
            
            //address_to_deposit[msg.sender].amount += msg.value; /// Will the msg indicate what token too, do we need a dif function for every ERC-20
            //address_to_deposit[msg.sender].success_destination = _success_destination;
            //address_to_deposit[msg.sender].fail_destination = _fail_destination;
            //userAddresses.push(msg.sender); //need an array to record these to iterate the mapping
        }
        else{
            // Increase the amount of the existing deposit by value of message
            address_to_deposit[msg.sender].amount += msg.value; /// Will the msg indicate what token too, do we need a dif function for every ERC-20
        }
    }
    
    //This is internal because nobody should have the power to distribute the eth other than the 'check' function
    function distribute_eth(bool _steps_reached) internal{
        //here goes the code to send the eth to the charity or the user depending if steps_reached is true or false
        if (_steps_reached){
                //for every deposit, transfer to success_destination
                for (uint i=0; i<userAddresses.length; i++) {
                    address add=userAddresses[i];
                    transfer( success_destination, address_to_deposit[add].amount); 
            }
        }
        else{
                // for every deposit, transfer to fail destination
                for (uint i=0; i<userAddresses.length; i++) {
                    address add=userAddresses[i];
                    transfer( address_to_deposit[add].fail_destination, address_to_deposit[add].amount);
            }
        }
    }
    
    function transfer(address payable to, uint256 amount) internal returns(bool){
        ///require(msg.sender==oracle address); no doing this elsewhere and with password
        to.transfer(amount);
    }
    
    // function for keeper to trigger which will check date and steps and distribute eth if appropriate
    function check() public returns(bool){

        uint256 steps = query_steps();
        
        if (steps >= steps_target){
            steps_reached=true;
        }
        if (query_date() >= date_target){ //Is it good to check ourselves incase the keeper lied?
            distribute_eth(steps_reached);
            return true;
        }
        else{
            return false;
        }
    }
    
    // KEEPERS STUFF
    
    
    function checkUpkeep(bytes calldata /* checkData */) external override returns (bool upkeepNeeded, bytes memory /* performData */) {
        upkeepNeeded = query_date() >= date_target;
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
        // don't think this is needed: return upkeepNeeded;
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        check();
        // We don't use the performData in this example. The performData is generated by the Keeper's call to your checkUpkeep function
    }
    
}