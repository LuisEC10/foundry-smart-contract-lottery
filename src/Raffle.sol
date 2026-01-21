// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/** 
  * @title A simple Raffle contract
  * @author Luis Espinoza
  * @notice this contract is for creating a simple Raffle
  * @dev Implements Chainlink VRF
*/
contract Raffle is VRFConsumerBaseV2Plus{
  /* Errors */
  error Raffle__SendMoreToEnterRaffle();
  error Raffle__TransferFailed();
  error Raffle__RaffleNotOpen();
  error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);
  
  /* Type declarations */
  enum RaffleState {
    OPEN,         // 0
    CALCULATING   // 1
  }

  /* State variables */
  uint16 private constant REQUEST_CONFIRMATIONS = 3;
  uint32 private constant NUM_WORDS = 1;
  uint256 private immutable i_entranceFee;
  // @dev The duration of the lottery in seconds
  uint256 private immutable i_interval;
  address payable[] private s_players; // Payable -> one of them is going to receive the money
  uint256 private s_lastTimeStamp;
  bytes32 private immutable i_keyHash;
  uint256 private immutable i_subscriptionId;
  uint32 private immutable i_callbackGasLimit;
  address private s_recentWinner;
  RaffleState private s_raffleState;

  /* Events */
  event RaffleEntered(address indexed player);
  event WinnerPicked(address indexed winner);
  event RequestedRaffleWinner(uint256 indexed requestId);

  constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator, bytes32 gasLane,
             uint256 subscriptionId, uint32 callbackGasLimit) VRFConsumerBaseV2Plus(vrfCoordinator){
    i_entranceFee = entranceFee;
    i_interval = interval;
    s_lastTimeStamp = block.timestamp;
    i_keyHash = gasLane;
    i_subscriptionId = subscriptionId;
    i_callbackGasLimit = callbackGasLimit;
    s_raffleState = RaffleState.OPEN;
  } 

  function enterRaffle() external payable {
    // require(msg.value >= I_ENTRANCEFEE, "Not enough ETH sent!"); 
    if(msg.value < i_entranceFee){
      revert Raffle__SendMoreToEnterRaffle();
    }
    
    if(s_raffleState != RaffleState.OPEN) {
      revert Raffle__RaffleNotOpen();
    }

    // payable(msg.sender) -> in order to have an address receive ETH
    s_players.push(payable(msg.sender));
    // Using Events helps:
    // 1. Makes migration easier
    // 2. Makes front end "indexing" easier
    emit RaffleEntered(msg.sender);
  }

  /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */
  function checkUpKeep(bytes memory /*checkdata*/) public view returns(bool upkeepNeeded, bytes memory /*performData*/) {
    bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval); 
    bool is_Open = s_raffleState == RaffleState.OPEN;
    bool hasBalance = address(this).balance > 0;
    bool hasPlayers = s_players.length > 0;
    upkeepNeeded = timeHasPassed && is_Open && hasBalance && hasPlayers;
    return (upkeepNeeded, "");
  } 

  // 1. Get a random number
  // 2. User random number to pick a player
  // 3. Be automatically called 

  function performUpkeep(bytes calldata /* performData */) external {
    // check to see if enough time has passed
    (bool upkeepNeeded, ) = checkUpKeep("");
    if(!upkeepNeeded) {
      revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
    }

    // Calculating state and it blocks the option to join the lottery
    s_raffleState = RaffleState.CALCULATING;
    // Get our random number
    // 1. Request RNG
    // 2. Get RNG
    uint256 requestId = s_vrfCoordinator.requestRandomWords(
      VRFV2PlusClient.RandomWordsRequest({
        keyHash: i_keyHash,
        subId: i_subscriptionId,
        requestConfirmations: REQUEST_CONFIRMATIONS,
        callbackGasLimit: i_callbackGasLimit,
        numWords: NUM_WORDS,
        extraArgs: VRFV2PlusClient._argsToBytes(
          // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
          VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
        )
      })
    );
    emit RequestedRaffleWinner(requestId);
  }

  // CEI: Checks, Effects, Interactinos Pattern
  function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal override {
    // Checks
    // Conditionals

    // Effect ( Internal Contract State )
    uint256 indexOfWinner = randomWords[0] % s_players.length;
    address payable recentWinner = s_players[indexOfWinner];
    s_recentWinner = recentWinner;
    s_raffleState = RaffleState.OPEN;
    s_players = new address payable[](0); // resset all the array to 0
    s_lastTimeStamp = block.timestamp;
    emit WinnerPicked(s_recentWinner);
    
    // Interactions -> ( External Contract Interactions )
    (bool success,) = recentWinner.call{value: address(this).balance}("");
    if(!success) {
      revert Raffle__TransferFailed();
    }
  }

  /**
  Getter functions
  */
  function getEntranceFee() external view returns(uint256) {
    return i_entranceFee;
  }

    function getRaffleState() external view returns(RaffleState) {
    return s_raffleState;
  }

  function getPlayer(uint256 indexOfPlayer) external view returns(address){
    return s_players[indexOfPlayer];
  }

  function getLasTimeStamp() external view returns(uint256) {
    return s_lastTimeStamp;
  }

  function getRecentWinner() external view returns(address) {
    return s_recentWinner;
  }
}
