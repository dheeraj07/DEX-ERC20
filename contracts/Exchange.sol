//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Exchange is Ownable{
    using Counters for Counters.Counter;

    struct Market
    {
        address _parentToken;
        address _tradeToken;
    }

    struct Order
    {
        uint _orderId;
        address _trader;
        Trade side;
        address _parentToken;
        address _tradeToken;
        uint _amount;
        uint _filled;
        uint _price;
        uint _timestamp;
    }

    enum Trade
    {
        BUY,
        SELL
    }

    address public feeAccount;
    uint public feePercent;
    mapping(address => mapping(address => uint)) public userBalances;
    mapping(string => mapping(uint => Order[])) public orderBook;
    mapping(string => Market) public marketsTraded;
    mapping(address => mapping(address => uint)) public pendingOrders;
    Counters.Counter public ordersCounter;
    Counters.Counter public tradesCounter;

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
        address _parentToken,
        address _tradeToken,
        uint _amount,
        uint _price,
        uint _timestamp
    );

    event OrderBookEve(
        Order[]
    );

    event TradeEve(
        uint _orderId,
        uint _tradeId,
        address _trader,
        address _counterParty,
        uint _tradeAmount,
        uint _feeAmount,
        uint _timestamp
    );

    event CancelEve(
        uint _orderId,
        address _trader,
        uint _timestamp
    );

    constructor(address _feeAccount, uint _feePercent)
    {
        feeAccount = _feeAccount;
        feePercent = _feePercent;
    }

    modifier isMarketActive(string memory _market) 
    {
        Market memory info = marketsTraded[_market];
        Market memory defaultInfo = Market(address(0), address(0));
        require(keccak256(abi.encode(info)) != keccak256(abi.encode(defaultInfo)), "Invalid Market Specified.");
        _;
    }

    modifier isBalanceInvolvedInTransaction(address _owner, address _token, uint _amount)
    {
        require((userBalances[_token][_owner] >= _amount) && ((userBalances[_token][_owner] - pendingOrders[_token][_owner]) >= _amount),"Cannot process this transaction due to pending orders.");
        _;
    }

    function RegisterMarket(address _parentToken, address _tradeToken, string memory _parentTokenSymbol, string memory _tradeTokenSymbol) 
    onlyOwner
    public
    {
        string memory marketName = string(abi.encodePacked(_parentTokenSymbol, _tradeTokenSymbol));
        marketsTraded[marketName] = Market(_parentToken, _tradeToken);
    }

    function isMarketEnabled(string memory _market)
    isMarketActive(_market)
    public
    view
    returns(bool)
    {
        return true;
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
    isBalanceInvolvedInTransaction(msg.sender, _token, _amount)
    public
    {
        withdraw(_token, msg.sender, _amount);
    }

    function withdrawToThirdParty(address _token, address _receiver, uint _amount)
    isBalanceInvolvedInTransaction(msg.sender, _token, _amount)
    public
    {
        withdraw(_token, _receiver, _amount);
    }

    function withdraw(address _token, address _receiver, uint _amount)
    isBalanceInvolvedInTransaction(msg.sender, _token, _amount)
    internal
    {
        require(userBalances[_token][msg.sender] >= _amount, "Insufficient balance.");

        userBalances[_token][msg.sender] -= _amount;
        IERC20(_token).transfer(_receiver, _amount);
        emit WithdrawEve(_token, _receiver, _amount);
    }

    function restrictTradeAction(address _owner, address _token, uint _amount)
    internal
    view
    returns(bool)
    {
        if((userBalances[_token][_owner] < _amount) || (userBalances[_token][_owner] - pendingOrders[_token][_owner]) < _amount)
        {
            return true;
        }
        return false;
    }

    function balanceOf(address _token, address _user) 
    public
    view 
    returns(uint)
    {
        return userBalances[_token][_user];
    }

    function getOrderBookLength(Trade _side, string memory _market)
    public
    view
    returns(uint)
    {
        return orderBook[_market][uint(_side)].length;
    }

    function limitOrder(uint _amount, uint _price, Trade _side, string memory _market) 
    isMarketActive(_market)
    public
    {
        Market memory currentMarket = marketsTraded[_market];
        if(_side == Trade.SELL)
        {
            require(!restrictTradeAction(msg.sender, currentMarket._parentToken, _amount), "Cannot process this transaction due to pending orders.");
            pendingOrders[currentMarket._parentToken][msg.sender] += _amount;
        }
        else if(_side == Trade.BUY)
        {
            require(!restrictTradeAction(msg.sender, currentMarket._tradeToken, _amount), "Cannot process this transaction due to pending orders.");
            pendingOrders[currentMarket._tradeToken][msg.sender] += ((_amount * _price)/(10 ** 18)); 
        }

        Order[] storage orders = orderBook[_market][uint(_side)];
        ordersCounter.increment();
        orders.push(Order(
            ordersCounter.current(),
            msg.sender,
            _side,
            currentMarket._parentToken,
            currentMarket._tradeToken,
            _amount,
            0,
            _price,
            block.timestamp
        ));
        sortTheArrayOrders(_market, _side);
        emit OrderBookEve(orderBook[_market][uint(_side)]);
        emit OrderEve(
        ordersCounter.current(),
        msg.sender,
        currentMarket._parentToken,
        currentMarket._tradeToken,
        _amount,
        _price,
        block.timestamp
        );
    }

    function marketOrder(uint _amount, uint _price, Trade _side, string memory _market) 
    isMarketActive(_market)
    public
    {
        Market memory currentMarket = marketsTraded[_market];
        if(_side == Trade.SELL)
        {
            require(userBalances[currentMarket._parentToken][msg.sender] >= _amount, "Insufficient balance.");
        }
        else if(_side == Trade.BUY)
        {
            uint currentMarketPrice = getMarketPrice(_market, Trade.SELL);
            require(userBalances[currentMarket._tradeToken][msg.sender] >= (currentMarketPrice <= 0 ? _amount :((currentMarketPrice * _amount)/(10 ** 18))), "Insufficient balance.");
        }

        Order[] storage orders = orderBook[_market][uint(_side == Trade.SELL ? Trade.BUY : Trade.SELL)];
        uint i = 0;
        uint remaining = _amount;
        uint feeAmount;
        uint originalOrdersLength = orders.length;

        while(i < orders.length && remaining > 0)
        {
            tradesCounter.increment();
            uint available = orders[i]._amount - orders[i]._filled;
            uint matched = (remaining > available) ? available : remaining;
            feeAmount = ((((matched * orders[i]._price)/(10 ** 18)) * feePercent)/(10 ** 20));
            if(_side == Trade.SELL)
            {
                require(!restrictTradeAction(msg.sender, currentMarket._parentToken, matched) && (originalOrdersLength == orders.length), "Cannot process this transaction due to pending orders.");
                if(restrictTradeAction(msg.sender, currentMarket._parentToken, matched))
                {
                    break;
                }

                pendingOrders[currentMarket._tradeToken][orders[i]._trader] -= ((matched * orders[i]._price)/(10 ** 18));

                userBalances[currentMarket._parentToken][msg.sender] -= matched;
                userBalances[currentMarket._tradeToken][msg.sender] += (((matched * orders[i]._price)/(10 ** 18)) - feeAmount);
                userBalances[currentMarket._tradeToken][feeAccount] += feeAmount;

                userBalances[currentMarket._parentToken][orders[i]._trader] += matched;
                userBalances[currentMarket._tradeToken][orders[i]._trader] -= ((matched * orders[i]._price)/(10 ** 18));
            }
            else if(_side == Trade.BUY)
            {
                require(!restrictTradeAction(msg.sender, currentMarket._tradeToken, ((matched * orders[i]._price)/(10 ** 18))) && (originalOrdersLength == orders.length), "Cannot process this transaction due to pending orders.");
                if(restrictTradeAction(msg.sender, currentMarket._tradeToken, (matched * orders[i]._price)/(10 ** 18)))
                {
                    break;
                }

                pendingOrders[currentMarket._parentToken][orders[i]._trader] -= matched;

                userBalances[currentMarket._parentToken][msg.sender] += (matched - feeAmount);
                userBalances[currentMarket._parentToken][feeAccount] += feeAmount;
                userBalances[currentMarket._tradeToken][msg.sender] -= ((matched * orders[i]._price)/(10 ** 18));

                userBalances[currentMarket._parentToken][orders[i]._trader] -= matched;
                userBalances[currentMarket._tradeToken][orders[i]._trader] += ((matched * orders[i]._price)/(10 ** 18));
            }
            remaining = remaining - matched;
            orders[i]._filled += matched;
            tradesCounter.increment();
            emit TradeEve(
                ordersCounter.current(),
                tradesCounter.current(),
                orders[i]._trader,
                msg.sender,
                matched,
                matched,
                block.timestamp
            );
            i++;
        }
        emit OrderBookEve(orderBook[_market][uint(_side)]);
        i = 0;
        while(i < orders.length && orders[i]._filled == orders[i]._amount)
        {
            for(uint j = i; j < orders.length - 1; j++)
            {
                orders[j] = orders[j+1];
            }
            orders.pop();
        }
        if(remaining > 0)
        {
            limitOrder(_amount, _price, _side, _market);
        }
    }

    function getMarketPrice(string memory _market, Trade _side)
    internal
    view
    returns(uint)
    {
        if(getOrderBookLength(_side, _market) > 0)
        {
            return orderBook[_market][uint(_side)][0]._price;
        }
        return 0;
    }

    function sortTheArrayOrders(string memory _market, Trade _side) 
    internal
    {
        Order[] storage orders = orderBook[_market][uint(_side)];
        if(_side == Trade.SELL)
        {
            quickSort(orders, int(0), int(orders.length - 1), false);
        }
        else if(_side == Trade.BUY)
        {
            quickSort(orders, int(0), int(orders.length - 1), true);
        }
        
    }

    function quickSort(Order[] storage _arr, int _left, int _right, bool _isBuy) 
    internal
    {
        int i = _left;
        int j = _right;
        if (i == j) return;
        uint pivot = _arr[uint(_left + (_right - _left) / 2)]._price;
        while (i <= j) 
        {
            if (_isBuy) 
            {
                while (_arr[uint(i)]._price > pivot) i++;
                while (pivot > _arr[uint(j)]._price) j--;
            } 
            else 
            {
                while (_arr[uint(i)]._price < pivot) i++;
                while (pivot < _arr[uint(j)]._price) j--;
            }
            if (i <= j) 
            {
                Order memory val = _arr[uint(i)];
                _arr[uint(i)] = _arr[uint(j)];
                _arr[uint(j)] = val;
                i++;
                j--;
            }
        }
        if (_left < j)
        {
            quickSort(_arr, _left, j, _isBuy);
        }
        if (i < _right)
        {
            quickSort(_arr, i, _right, _isBuy);
        }
    }

    function cancelOrder(uint _orderId, Trade _side, string memory _market)
    public
    returns(bool)
    {
        require(_orderId <= ordersCounter.current(), "Invalid Order.");
        Order[] storage orders = orderBook[_market][uint(_side)];
        uint i = 0;
        uint initialOrderBooklength = orders.length;
        while(i < orders.length)
        {
            if(orders[i]._orderId == _orderId)
            {
                require(orders[i]._filled == 0 && orders[i]._trader == msg.sender, "Not authorized to cancel this order.");
                if(i != orders.length - 1)
                {
                    for(uint j = i; j < orders.length - 1; j++)
                    {
                        orders[j] = orders[j+1];
                    }
                }
                orders.pop();
                emit CancelEve(_orderId, msg.sender, block.timestamp);
                break;
            }
            i++;
        }
        return initialOrderBooklength == orders.length+1;
    }
}