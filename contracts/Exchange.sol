//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/*
Todo:
1. Check if there are any pending orders before withdrawl.
2. Allow partial order fullfills.
3. When cancelling the order, make sure if the order is not partially fullfilled. 
*/

contract Exchange{
    using Counters for Counters.Counter;

    address public feeAccount;
    uint public feePercent;
    mapping(address => mapping(address => uint)) public userBalances;
    mapping(uint => bool) public ordersCancelled;
    mapping(uint => bool) public ordersFilled;
    mapping(uint => Order) ordersInfo;
    Counters.Counter public ordersCounter;

    event DepositEve(
        address _tokenAddress, 
        address _userAddress, 
        uint _amount
    );

    event WithdrawEve(
        address _tokenAddress, 
        address _receiverAddress, 
        uint _amount
    );

    event OrderEve(
        uint _orderId,
        address _trader,
        address _tokenBuy,
        address _tokenSell,
        uint _amountBuy,
        uint _amountSell,
        uint _timestamp
    );

    event CancelEve(
        uint _orderId,
        address _trader,
        address _tokenBuy,
        address _tokenSell,
        uint _amountBuy,
        uint _amountSell,
        uint _timestamp
    );

    event TradeEve(
        uint _orderId,
        address _orderMaker,
        address _orderTaker,
        address _tokenBuy,
        address _tokenSell,
        uint _amountBuy,
        uint _feeAmount,
        uint _amountSell,
        uint _timestamp
    );

    struct Order
    {
        uint _orderId;
        address _trader;
        address _tokenBuy;
        address _tokenSell;
        uint _amountBuy;
        uint _amountSell;
        uint _timestamp;
    }

    constructor(address _feeAccount, uint _feePercent)
    {
        feeAccount = _feeAccount;
        feePercent = _feePercent;
    }

    function depositToken(address _token, uint _amount) 
    public
    {
        require(IERC20(_token).balanceOf(msg.sender) >= _amount, "Insufficient balance.");
        require(IERC20(_token).allowance(msg.sender,(address(this))) >= _amount, "Insufficient allowance.");

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        userBalances[_token][msg.sender] += _amount;
        emit DepositEve(_token, msg.sender, _amount);
    }

    function withdrawTokens(address _token, uint _amount) 
    public
    {
        withdraw(_token, msg.sender, _amount);
    }

    function withdrawToThirdParty(address _token, address _receiver, uint _amount) 
    public
    {
        withdraw(_token, _receiver, _amount);
    }

    function withdraw(address _token, address _receiver, uint _amount) 
    internal
    {
        require(userBalances[_token][msg.sender] >= _amount, "Insufficient balance.");

        userBalances[_token][msg.sender] -= _amount;
        IERC20(_token).transfer(_receiver, _amount);
        emit WithdrawEve(_token, _receiver, _amount);
    }

    function balanceOf(address _token, address _user) 
    public
    view 
        returns(uint)
    {
        return userBalances[_token][_user];
    }

    function makeOrder(address _tokenBuy, address _tokenSell, uint _amountBuy, uint _amountSell)   
    public
    {
        require(balanceOf(_tokenSell, msg.sender) >= _amountSell, "Insufficient balance.");

        ordersCounter.increment();
        ordersInfo[ordersCounter.current()] = Order(ordersCounter.current(), msg.sender, _tokenBuy, _tokenSell, _amountBuy, _amountSell, block.timestamp);
        emit OrderEve(ordersCounter.current(), msg.sender, _tokenBuy, _tokenSell, _amountBuy, _amountSell, block.timestamp);
    }


    function cancelOrder(uint _orderId) 
    public
    {
        Order storage order = ordersInfo[_orderId];
        require(order._orderId == _orderId, "Invalid trade order.");
        require(order._trader == msg.sender, "Insufficient privileages.");
        

        ordersCancelled[_orderId] = true;

        emit CancelEve(order._orderId, msg.sender, order._tokenBuy, order._tokenSell, order._amountBuy, order._amountSell, block.timestamp);
    }

    function fillOrder(uint _orderId) 
    public
    {
         Order storage order = ordersInfo[_orderId];
         require(_orderId <= ordersCounter.current() && _orderId > 0, "Invalid Order.");
         require(userBalances[order._tokenBuy][msg.sender] >= order._amountBuy,"Insufficient amount.");

         fullFillTrade(order._orderId,order._trader,order._tokenBuy,order._tokenSell,order._amountBuy,order._amountSell);

         ordersFilled[_orderId] = true;
    }

    function fullFillTrade(
        uint _orderId,
        address _trader,
        address _tokenBuy,
        address _tokenSell,
        uint _amountBuy,
        uint _amountSell
    ) 
    internal
    {
        require(!ordersCancelled[_orderId], "Order is cancelled.");
        require(!ordersFilled[_orderId], "Order is filled already.");

        uint feeAmount = (_amountSell * feePercent) / 100;

        userBalances[_tokenBuy][msg.sender] -= (_amountBuy + feeAmount);
        userBalances[_tokenBuy][_trader] += _amountBuy;

        userBalances[_tokenSell][msg.sender] += (_amountSell);
        userBalances[_tokenSell][_trader] -= _amountSell;

        userBalances[_tokenBuy][feeAccount] += feeAmount;

        emit TradeEve(_orderId, _trader, msg.sender, _tokenBuy, _tokenSell, _amountBuy, feeAmount, _amountSell, block.timestamp);
    }
}