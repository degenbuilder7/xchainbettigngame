//SPDX-License-Identifier: MIT
/*******************************************
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~ XChain BETTING  ~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
--------------------------------------------
      3 6 9 12 15 18 21 24 27 30 33 36
    0 2 5 8 11 14 17 20 23 26 29 32 35
      1 4 7 10 13 16 19 22 25 28 31 34
--------------------------------------------  
 <Even|Odd> ~~ <Black|Red> ~~ <1st|2nd> ~~ <1st|2nd|3rd> 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

/*** @notice on-chain Betting Game using ChainLink VRFV2.
 *** Immutable after deployment except for setSponserwallet().
 *** Only supports one bet (single number, black/red, even/odd, 1st/2nd or 1st/2nd/3rd of board) per spin.
 *** User places bet by calling applicable payable function, then calls spinRouletteWheel(),
 *** then calls checkIf[BetType]Won() after VRF responds with spinResult for user
 *** following the applicable chain's minimum confirmations (25 for Optimism)
 *** hardcoded minimum bet of .001 ETH to prevent spam of sponsorWallet, winnings paid from this contract **/
/// @title OnchainBetting
/// Roulette odds should prevent the casino (this contract) and sponsorWallet from bankruptcy, but anyone can refill by sending ETH directly to address

pragma solidity >=0.8.4;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract OnchainBetting is VRFConsumerBaseV2Plus {
  uint256 public constant MIN_BET = 10000000000000; // .001 ETH
  uint256 spinCount;
  address airnode;
  address immutable deployer;
  address payable sponsorWallet;
  bytes32 endpointId;

  // chainlink vrf 

      event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */

    // Your subscription ID.
    uint256 public s_subscriptionId;

    // Past request IDs.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2-5/supported-networks
    bytes32 public keyHash =
        0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 public callbackGasLimit = 100000;

    // The default is 3, but you can set this higher.
    uint16 public requestConfirmations = 1;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2_5.MAX_NUM_WORDS.
    uint32 public numWords = 1;

  // ~~~~~~~ ENUMS ~~~~~~~

  enum BetType {
    Color,
    Number,
    EvenOdd,
    Third,
	 Half
  }

  // ~~~~~~~ MAPPINGS ~~~~~~~

  mapping(address => bool) public userBetAColor;
  mapping(address => bool) public userBetANumber;
  mapping(address => bool) public userBetEvenOdd;
  mapping(address => bool) public userBetThird;
  mapping(address => bool) public userBetHalf;
  mapping(address => bool) public userToColor;
  mapping(address => bool) public userToEven;

  mapping(address => uint256) public userToCurrentBet;
  mapping(address => uint256) public userToSpinCount;
  mapping(address => uint256) public userToNumber;
  mapping(address => uint256) public userToThird;
  mapping(address => uint256) public userToHalf;

  mapping(uint256 => bool) expectingRequestWithIdToBeFulfilled;

  mapping(uint256 => uint256) public requestIdToSpinCount;
  mapping(uint256 => uint256) public requestIdToResult;

  mapping(uint256 => bool) blackNumber;
  mapping(uint256 => bool) public blackSpin;
  mapping(uint256 => bool) public spinIsComplete;

  mapping(uint256 => BetType) public spinToBetType;
  mapping(uint256 => address) public spinToUser;
  mapping(uint256 => uint256) public spinResult;
  uint256 public finalNumber;

  // ~~~~~~~ ERRORS ~~~~~~~

  error HouseBalanceTooLow();
  error NoBet();
  error ReturnFailed();
  error SpinNotComplete();
  error TransferToDeployerWalletFailed();
  error TransferToSponsorWalletFailed();

  // ~~~~~~~ EVENTS ~~~~~~~

  event RequestedUint256(uint256 requestId);
  event ReceivedUint256(uint256 indexed requestId, uint256 response);
  event SpinComplete(uint256 indexed requestId, uint256 indexed spinNumber, uint256 qrngResult);
  event WinningNumber(uint256 indexed spinNumber, uint256 winningNumber);

  /// sponsorWallet must be derived from address(this) after deployment

    constructor(
        uint256 subscriptionId
    ) VRFConsumerBaseV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B) {
        s_subscriptionId = subscriptionId;
            deployer = msg.sender;
            blackNumber[2] = true;
            blackNumber[4] = true;
            blackNumber[6] = true;
            blackNumber[8] = true;
            blackNumber[10] = true;
            blackNumber[11] = true;
            blackNumber[13] = true;
            blackNumber[15] = true;
            blackNumber[17] = true;
            blackNumber[20] = true;
            blackNumber[22] = true;
            blackNumber[24] = true;
            blackNumber[26] = true;
            blackNumber[28] = true;
            blackNumber[29] = true;
            blackNumber[31] = true;
            blackNumber[33] = true;
            blackNumber[35] = true;
    }


  /// @notice for user to spin after bet is placed
  /// @param _spinCount the msg.sender's spin number assigned when bet placed
  function _spinRouletteWheel(uint256 _spinCount) internal {
    require(!spinIsComplete[_spinCount], "spin already complete");
    require(_spinCount == userToSpinCount[msg.sender], "!= msg.sender spinCount");

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false
                    })
                )
            })
        );
    expectingRequestWithIdToBeFulfilled[requestId] = true;
    requestIdToSpinCount[requestId] = _spinCount;
    emit RequestedUint256(requestId);
  }

  /** @dev chainlinkvrf will call back with a response
   *** if no response returned (0) user will have bet returned (see check functions) */
  function fulfillRandomWords(uint256 requestId, uint256[] calldata _randomWords) internal override  {
    require(expectingRequestWithIdToBeFulfilled[requestId], "Unexpected Request ID");
    expectingRequestWithIdToBeFulfilled[requestId] = false;
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomWords = _randomWords;
    uint256 _qrngUint256 = _randomWords[0];
    requestIdToResult[requestId] = _qrngUint256;
    _spinComplete(requestId, _qrngUint256);
    finalNumber = (_qrngUint256 % 37);
    emit ReceivedUint256(requestId, _qrngUint256);
  }

  /** @dev a failed fulfill (return 0) assigned 37 to avoid modulo problem
   *** in spinResult calculations in above functions,
   *** otherwise assigns the QRNG result to the applicable spin number **/
  function _spinComplete(uint256 _requestId, uint256 _qrngUint256) internal {
    uint256 _spin = requestIdToSpinCount[_requestId];
    if (_qrngUint256 == 0) {
      spinResult[_spin] = 37;
    } else {
      spinResult[_spin] = _qrngUint256;
    }
    spinIsComplete[_spin] = true;
    if (spinToBetType[_spin] == BetType.Number) {
      checkIfNumberWon(_spin);
    } else if (spinToBetType[_spin] == BetType.Color) {
      checkIfColorWon(_spin);
    } else if (spinToBetType[_spin] == BetType.EvenOdd) {
      checkIfEvenOddWon(_spin);
	 } else if (spinToBetType[_spin] == BetType.Half) {
		checkIfHalfWon(_spin);
    } else if (spinToBetType[_spin] == BetType.Third) {
      checkIfThirdWon(_spin);
    }
    emit SpinComplete(_requestId, _spin, spinResult[_spin]);
  }

  function setSponserwallet(address payable _sponsorWallet) external {
    require(msg.sender == deployer, "msg.sender not deployer");
    sponsorWallet = _sponsorWallet;
  }


  function topUpSponsorWallet() external payable {
    require(msg.value != 0, "msg.value == 0");
    (bool sent, ) = sponsorWallet.call{ value: msg.value }("");
    if (!sent) revert TransferToSponsorWalletFailed();
  }

  // to refill the "house" (address(this)) if bankrupt
  receive() external payable {}

  /// @notice for user to submit a single-number bet, which pays out 35:1 if correct after spin
  /// @param _numberBet number between 0 and 36
  /// @return userToSpinCount[msg.sender] spin count for this msg.sender, to enter in spinRouletteWheel()
  function betNumber(uint256 _numberBet) external payable returns (uint256) {
    require(_numberBet < 37, "_numberBet is > 36");
    require(msg.value >= MIN_BET, "msg.value < MIN_BET");
    if (address(this).balance < msg.value * 35) revert HouseBalanceTooLow();
    userToCurrentBet[msg.sender] = msg.value;
    unchecked {
      ++spinCount;
    }
    userToSpinCount[msg.sender] = spinCount;
    spinToUser[spinCount] = msg.sender;
    userToNumber[msg.sender] = _numberBet;
    userBetANumber[msg.sender] = true;
    spinToBetType[spinCount] = BetType.Number;
    _spinRouletteWheel(spinCount);
    return (userToSpinCount[msg.sender]);
  }

  /// @notice for user to check number bet result when spin complete
  /// @dev unsuccessful bet sends 10% to sponsor wallet to ensure future fulfills, 2% to deployer, rest kept by house
  function checkIfNumberWon(uint256 _spin) internal returns (uint256) {
    address _user = spinToUser[_spin];
    if (userToCurrentBet[_user] == 0) revert NoBet();
    if (!userBetANumber[_user]) revert NoBet();
    if (!spinIsComplete[_spin]) revert SpinNotComplete();
    if (spinResult[_spin] == 37) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] }("");
      if (!sent) revert ReturnFailed();
    } else {}
    if (userToNumber[_user] == spinResult[_spin] % 37) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 35 }("");
      if (!sent) revert HouseBalanceTooLow();
    } else {
      (bool sent, ) = sponsorWallet.call{ value: userToCurrentBet[_user] / 10 }("");
      if (!sent) revert TransferToSponsorWalletFailed();
      (bool sent2, ) = deployer.call{ value: userToCurrentBet[_user] / 50 }("");
      if (!sent2) revert TransferToDeployerWalletFailed();
    }
    userToCurrentBet[_user] = 0;
    userBetANumber[_user] = false;
    emit WinningNumber(_spin, spinResult[_spin] % 37);
    return (spinResult[_spin] % 37);
  }

  /// @notice submit bet and "1", "2", or "3" for a bet on 1st/2nd/3rd of table, which pays out 3:1 if correct after spin
  /// @param _oneThirdBet uint 1, 2, or 3 to represent first, second or third of table
  /// @return userToSpinCount[msg.sender] spin count for this msg.sender, to enter in spinRouletteWheel()
  function betOneThird(uint256 _oneThirdBet) external payable returns (uint256) {
    require(_oneThirdBet == 1 || _oneThirdBet == 2 || _oneThirdBet == 3, "_oneThirdBet not 1 or 2 or 3");
    require(msg.value >= MIN_BET, "msg.value < MIN_BET");
    if (address(this).balance < msg.value * 3) revert HouseBalanceTooLow();
    userToCurrentBet[msg.sender] = msg.value;
    unchecked {
      ++spinCount;
    }
    spinToUser[spinCount] = msg.sender;
    userToSpinCount[msg.sender] = spinCount;
    userToThird[msg.sender] = _oneThirdBet;
    userBetThird[msg.sender] = true;
    spinToBetType[spinCount] = BetType.Third;
    _spinRouletteWheel(spinCount);
    return (userToSpinCount[msg.sender]);
  }

  /// @notice for user to check third bet result when spin complete
  /// @dev unsuccessful bet sends 10% to sponsor wallet to ensure future fulfills, 2% to deployer, rest kept by house
  function checkIfThirdWon(uint256 _spin) internal returns (uint256) {
    address _user = spinToUser[_spin];
    if (userToCurrentBet[_user] == 0) revert NoBet();
    if (!userBetThird[_user]) revert NoBet();
    if (!spinIsComplete[_spin]) revert SpinNotComplete();
    uint256 _result = spinResult[_spin] % 37;
    uint256 _thirdResult;
    if (_result > 0 && _result < 13) {
      _thirdResult = 1;
    } else if (_result > 12 && _result < 25) {
      _thirdResult = 2;
    } else if (_result > 24) {
      _thirdResult = 3;
    }
    if (spinResult[_spin] == 37) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] }("");
      if (!sent) revert ReturnFailed();
    } else {}
    if (userToThird[_user] == 1 && _thirdResult == 1) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 3 }("");
      if (!sent) revert HouseBalanceTooLow();
    } else if (userToThird[_user] == 2 && _thirdResult == 2) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 3 }("");
      if (!sent) revert HouseBalanceTooLow();
    } else if (userToThird[_user] == 3 && _thirdResult == 3) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 3 }("");
      if (!sent) revert HouseBalanceTooLow();
    } else {
      (bool sent, ) = sponsorWallet.call{ value: userToCurrentBet[_user] / 10 }("");
      if (!sent) revert TransferToSponsorWalletFailed();
      (bool sent2, ) = deployer.call{ value: userToCurrentBet[_user] / 50 }("");
      if (!sent2) revert TransferToDeployerWalletFailed();
    }
    userToCurrentBet[_user] = 0;
    userBetThird[_user] = false;
    emit WinningNumber(_spin, spinResult[_spin] % 37);
    return (spinResult[_spin] % 37);
  }

  // make similar function as above for halves
    /// @notice submit bet and "1" or "2" for a bet on 1st/2nd/3rd of table, which pays out 2:1 if correct after spin
  /// @param _halfBet uint 1 or 2 to represent first or second half of table
  /// @return userToSpinCount[msg.sender] spin count for this msg.sender, to enter in spinRouletteWheel()
  function betHalf(uint256 _halfBet) external payable returns (uint256) {
	 require(_halfBet == 1 || _halfBet == 2, "_halfBet not 1 or 2");
	 require(msg.value >= MIN_BET, "msg.value < MIN_BET");
	 if (address(this).balance < msg.value * 2) revert HouseBalanceTooLow();
	 userToCurrentBet[msg.sender] = msg.value;
	 unchecked {
		++spinCount;
	 }
	 spinToUser[spinCount] = msg.sender;
	 userToSpinCount[msg.sender] = spinCount;
	 userToHalf[msg.sender] = _halfBet;
	 userBetHalf[msg.sender] = true;
	 spinToBetType[spinCount] = BetType.Half;
	 _spinRouletteWheel(spinCount);
	 return (userToSpinCount[msg.sender]);
  }

  /// @notice for user to check half bet result when spin complete
  /// @dev unsuccessful bet sends 10% to sponsor wallet to ensure future fulfills, 2% to deployer, rest kept by house
  function checkIfHalfWon(uint256 _spin) internal returns (uint256) {
	 address _user = spinToUser[_spin];
	 if (userToCurrentBet[_user] == 0) revert NoBet();
	 if (!userBetHalf[_user]) revert NoBet();
	 if (!spinIsComplete[_spin]) revert SpinNotComplete();
	 uint256 _result = spinResult[_spin] % 37;
	 uint256 _halfResult;
	 if (_result > 0 && _result < 19) {
		_halfResult = 1;
	 } else if (_result > 18) {
		_halfResult = 2;
	 }
	 if (spinResult[_spin] == 37) {
		(bool sent, ) = _user.call{ value: userToCurrentBet[_user] }("");
		if (!sent) revert ReturnFailed();
	 } else {}
	 if (userToHalf[_user] == 1 && _halfResult == 1) {
		(bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 2 }("");
		if (!sent) revert HouseBalanceTooLow();
	 } else if (userToHalf[_user] == 2 && _halfResult == 2) {
		(bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 2 }("");
		if (!sent) revert HouseBalanceTooLow();
	 } else {
		(bool sent, ) = sponsorWallet.call{ value: userToCurrentBet[_user] / 10 }("");
		if (!sent) revert TransferToSponsorWalletFailed();
		(bool sent2, ) = deployer.call{ value: userToCurrentBet[_user] / 50 }("");
		if (!sent2) revert TransferToDeployerWalletFailed();
	 }
	 userToCurrentBet[_user] = 0;
	 userBetHalf[_user] = false;
	 emit WinningNumber(_spin, spinResult[_spin] % 37);
	 return (spinResult[_spin] % 37);
  }




  /** @notice for user to submit a boolean even or odd bet, which pays out 2:1 if correct
   *** reminder that a return of 0 is neither even nor odd in roulette **/
  /// @param _isEven boolean bet, true for even
  /// @return userToSpinCount[msg.sender] spin count for this msg.sender, to enter in spinRouletteWheel()
  function betEvenOdd(bool _isEven) external payable returns (uint256) {
    require(msg.value >= MIN_BET, "msg.value < MIN_BET");
    if (address(this).balance < msg.value * 2) revert HouseBalanceTooLow();
    unchecked {
      ++spinCount;
    }
    spinToUser[spinCount] = msg.sender;
    userToCurrentBet[msg.sender] = msg.value;
    userToSpinCount[msg.sender] = spinCount;
    userBetEvenOdd[msg.sender] = true;
    if (_isEven) {
      userToEven[msg.sender] = true;
    } else {}
    spinToBetType[spinCount] = BetType.EvenOdd;
    _spinRouletteWheel(spinCount);
    return (userToSpinCount[msg.sender]);
  }

  /// @notice for user to check even/odd bet result when spin complete
  /// @dev unsuccessful bet sends 10% to sponsor wallet to ensure future fulfills, 2% to deployer, rest kept by house
  function checkIfEvenOddWon(uint256 _spin) internal returns (uint256) {
    address _user = spinToUser[_spin];
    if (userToCurrentBet[_user] == 0) revert NoBet();
    if (!userBetEvenOdd[_user]) revert NoBet();
    if (!spinIsComplete[_spin]) revert SpinNotComplete();
    uint256 _result = spinResult[_spin] % 37;
    if (spinResult[_spin] == 37) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] }("");
      if (!sent) revert ReturnFailed();
    } else {}
    if (_result == 0) {
      (bool sent, ) = sponsorWallet.call{ value: userToCurrentBet[_user] / 10 }("");
      if (!sent) revert TransferToSponsorWalletFailed();
    } else if (userToEven[_user] && (_result % 2 == 0)) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 2 }("");
      if (!sent) revert HouseBalanceTooLow();
    } else if (!userToEven[_user] && _result % 2 != 0) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 2 }("");
      if (!sent) revert HouseBalanceTooLow();
    } else {
      (bool sent, ) = sponsorWallet.call{ value: userToCurrentBet[_user] / 10 }("");
      if (!sent) revert TransferToSponsorWalletFailed();
      (bool sent2, ) = deployer.call{ value: userToCurrentBet[_user] / 50 }("");
      if (!sent2) revert TransferToDeployerWalletFailed();
    }
    userBetEvenOdd[_user] = false;
    userToCurrentBet[_user] = 0;
    emit WinningNumber(_spin, spinResult[_spin] % 37);
    return (spinResult[_spin] % 37);
  }

  /** @notice for user to submit a boolean black or red bet, which pays out 2:1 if correct
   *** reminder that 0 is neither red nor black in roulette **/
  /// @param _isBlack boolean bet, true for black, false for red
  /// @return userToSpinCount[msg.sender] spin count for this msg.sender, to enter in spinRouletteWheel()
  function betColor(bool _isBlack) external payable returns (uint256) {
    require(msg.value >= MIN_BET, "msg.value < MIN_BET");
    if (address(this).balance < msg.value * 2) revert HouseBalanceTooLow();
    unchecked {
      ++spinCount;
    }
    spinToUser[spinCount] = msg.sender;
    userToCurrentBet[msg.sender] = msg.value;
    userToSpinCount[msg.sender] = spinCount;
    userBetAColor[msg.sender] = true;
    if (_isBlack) {
      userToColor[msg.sender] = true;
    } else {}
    spinToBetType[spinCount] = BetType.Color;
    _spinRouletteWheel(spinCount);
    return (userToSpinCount[msg.sender]);
  }

  /// @notice for user to check color bet result when spin complete
  /// @dev unsuccessful bet sends 10% to sponsor wallet to ensure future fulfills, 2% to deployer, rest kept by house
  function checkIfColorWon(uint256 _spin) internal returns (uint256) {
    address _user = spinToUser[_spin];
    if (userToCurrentBet[_user] == 0) revert NoBet();
    if (!userBetAColor[_user]) revert NoBet();
    if (!spinIsComplete[_spin]) revert SpinNotComplete();
    uint256 _result = spinResult[_spin] % 37;
    if (spinResult[_spin] == 37) {
      (bool sent, ) = _user.call{ value: userToCurrentBet[_user] }("");
      if (!sent) revert ReturnFailed();
    } else if (_result == 0) {
      (bool sent, ) = sponsorWallet.call{ value: userToCurrentBet[_user] / 10 }("");
      if (!sent) revert TransferToSponsorWalletFailed();
      (bool sent2, ) = deployer.call{ value: userToCurrentBet[_user] / 50 }("");
      if (!sent2) revert TransferToDeployerWalletFailed();
    } else {
      if (blackNumber[_result]) {
        blackSpin[_spin] = true;
      } else {}
      if (userToColor[_user] && blackSpin[_spin]) {
        (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 2 }("");
        if (!sent) revert HouseBalanceTooLow();
      } else if (!userToColor[_user] && !blackSpin[_spin] && _result != 0) {
        (bool sent, ) = _user.call{ value: userToCurrentBet[_user] * 2 }("");
        if (!sent) revert HouseBalanceTooLow();
      } else {
        (bool sent, ) = sponsorWallet.call{ value: userToCurrentBet[_user] / 10 }("");
        if (!sent) revert TransferToSponsorWalletFailed();
        (bool sent2, ) = deployer.call{ value: userToCurrentBet[_user] / 50 }("");
        if (!sent2) revert TransferToDeployerWalletFailed();
      }
    }
    userBetAColor[_user] = false;
    userToCurrentBet[_user] = 0;
    emit WinningNumber(_spin, spinResult[_spin] % 37);
    return (spinResult[_spin] % 37);
  }
}