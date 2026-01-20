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

  /* Events */
  event RaffleEntered(address indexed player);

  constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator, bytes32 gasLane,
             uint256 subscriptionId, uint32 callbackGasLimit) VRFConsumerBaseV2Plus(vrfCoordinator){
    i_entranceFee = entranceFee;
    i_interval = interval;
    s_lastTimeStamp = block.timestamp;
    i_keyHash = gasLane;
    i_subscriptionId = subscriptionId;
    i_callbackGasLimit = callbackGasLimit;
  } 

  function enterRaffle() external payable {
    // require(msg.value >= I_ENTRANCEFEE, "Not enough ETH sent!"); 
    if(msg.value < i_entranceFee){
      revert Raffle__SendMoreToEnterRaffle();
    }
    // payable(msg.sender) -> in order to have an address receive ETH
    s_players.push(payable(msg.sender));
    // Using Events helps:
    // 1. Makes migration easier
    // 2. Makes front end "indexing" easier
    emit RaffleEntered(msg.sender);
  }

  // 1. Get a random number
  // 2. User random number to pick a player
  // 3. Be automatically called 
  function pickWinner() external {
    // check to see if enough time has passed
    if(block.timestamp - s_lastTimeStamp < i_interval){
      revert();
    }
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
  }

  function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
    
  }

  /**
  Getter functions
  */
  function getEntranceFee() external view returns(uint256) {
    return i_entranceFee;
  }
}
