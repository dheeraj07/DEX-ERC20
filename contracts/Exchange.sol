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

    constructor(address _feeAccount, uint _feePercent)
    {
        feeAccount = _feeAccount;
        feePercent = _feePercent;
    }

    modifier isMarketActive(string memory market) 
    {
        Market memory info = marketsTraded[market];
        Market memory defaultInfo = Market(address(0), address(0));
        require(keccak256(abi.encode(info)) != keccak256(abi.encode(defaultInfo)), "Invalid Market Specified.");
        _;
    }

    function RegisterMarket(address parentToken, address childToken, string memory parentTokenSymbol, string memory childTokenSymbol) 
    public
    onlyOwner
    {
        string memory marketName = string(abi.encodePacked(parentTokenSymbol, childTokenSymbol));
        marketsTraded[marketName] = Market(parentToken, childToken);
    }

    function isMarketEnabled(string memory market)
    public
    view
    isMarketActive(market)
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

    function getOrderBookLength(Trade side, string memory market)
    public
    view
    returns(uint)
    {
        return orderBook[market][uint(side)].length;
    }

    function limitOrder(uint amount, uint price, Trade side, string memory market) 
    isMarketActive(market)
    public
    {
        Market memory info = marketsTraded[market];
        address parentToken = info._parentToken;
        address tradeToken = info._tradeToken;

        if(side == Trade.SELL)
        {
            require(userBalances[parentToken][msg.sender] >= amount, "Insufficient balance.");
        }
        else if(side == Trade.BUY)
        {
            require(userBalances[tradeToken][msg.sender] >= amount, "Insufficient balance.");
        }

        Order[] storage orders = orderBook[market][uint(side)];
        ordersCounter.increment();
        orders.push(Order(
            ordersCounter.current(),
            msg.sender,
            side,
            parentToken,
            tradeToken,
            amount,
            0,
            price,
            block.timestamp
        ));
        sortTheArrayOrders(market, side);
        emit OrderBookEve(orderBook[market][uint(side)]);
        emit OrderEve(
        ordersCounter.current(),
        msg.sender,
        parentToken,
        tradeToken,
        amount,
        price,
        block.timestamp
        );
    }

    function marketOrder(uint amount, Trade side, string memory market) 
    isMarketActive(market)
    public
    {
        Market memory info = marketsTraded[market];
        address parentToken = info._parentToken;
        address tradeToken = info._tradeToken;

        if(side == Trade.SELL)
        {
            require(userBalances[parentToken][msg.sender] >= amount, "Insufficient balance.");
        }
        else if(side == Trade.BUY)
        {
            uint currentMarketPrice = getMarketPrice(market, Trade.SELL);
            require(userBalances[tradeToken][msg.sender] >= (currentMarketPrice <= 0 ? amount :((currentMarketPrice * amount)/(10 ** 18))), "Insufficient balance.");
        }

        Order[] storage orders = orderBook[market][uint(side == Trade.SELL ? Trade.BUY : Trade.SELL)];
        uint i;
        uint remaining = amount;
        uint feeAmount;
        uint lastPrice;

        while(i < orders.length && remaining > 0)
        {
            tradesCounter.increment();
            uint available = orders[i]._amount - orders[i]._filled;
            uint matched = (remaining > available) ? available : remaining;
            feeAmount = ((((matched * orders[i]._price)/(10 ** 18)) * feePercent)/(10 ** 20));
            lastPrice = orders[i]._price;
            if(side == Trade.SELL)
            {
                if(userBalances[parentToken][msg.sender] < matched)
                {
                    break;
                }

                userBalances[parentToken][msg.sender] -= matched;
                userBalances[tradeToken][msg.sender] += (((matched * orders[i]._price)/(10 ** 18)) - feeAmount);
                userBalances[tradeToken][feeAccount] += feeAmount;

                userBalances[parentToken][orders[i]._trader] += matched;
                userBalances[tradeToken][orders[i]._trader] -= ((matched * orders[i]._price)/(10 ** 18));
            }
            else if(side == Trade.BUY)
            {
                if(userBalances[tradeToken][msg.sender] < ((matched * orders[i]._price)/(10 ** 18)))
                {
                    break;
                }

                userBalances[parentToken][msg.sender] += (matched - feeAmount) ;
                userBalances[parentToken][feeAccount] += feeAmount;
                userBalances[tradeToken][msg.sender] -= ((matched * orders[i]._price)/(10 ** 18));

                userBalances[parentToken][orders[i]._trader] -= matched;
                userBalances[tradeToken][orders[i]._trader] += ((matched * orders[i]._price)/(10 ** 18));
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
        emit OrderBookEve(orderBook[market][uint(side)]);
        i = 0;
        while(i < orders.length && orders[i]._filled == orders[i]._amount)
        {
            for(uint j = i; j < orders.length - 1; j++)
            {
                orders[j] = orders[j+1];
            }
            orders.pop();
        }
        //Need to handle logic for market -> limit order price
        if(remaining > 0)
        {
            limitOrder(amount, lastPrice, side, market);
        }
    }

    function getMarketPrice(string memory market, Trade side)
    internal
    view
    returns(uint)
    {
        if(getOrderBookLength(side, market) > 0)
        {
            return orderBook[market][uint(side)][0]._price;
        }
        return 0;
    }

    function sortTheArrayOrders(string memory info, Trade side) 
    internal
    {
        Order[] storage orders = orderBook[info][uint(side)];
        if(side == Trade.SELL)
        {
            quickSort(orders, int(0), int(orders.length - 1), false);
        }
        else if(side == Trade.BUY)
        {
            quickSort(orders, int(0), int(orders.length - 1), true);
        }
        
    }

    function quickSort(Order[] storage arr, int left, int right, bool isBuy) 
    internal
    {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)]._price;
        while (i <= j) 
        {
            if (isBuy) 
            {
                while (arr[uint(i)]._price > pivot) i++;
                while (pivot > arr[uint(j)]._price) j--;
            } 
            else 
            {
                while (arr[uint(i)]._price < pivot) i++;
                while (pivot < arr[uint(j)]._price) j--;
            }
            if (i <= j) 
            {
                Order memory val = arr[uint(i)];
                arr[uint(i)] = arr[uint(j)];
                arr[uint(j)] = val;
                i++;
                j--;
            }
        }
        if (left < j)
        {
            quickSort(arr, left, j, isBuy);
        }
        if (i < right)
        {
            quickSort(arr, i, right, isBuy);
        }
    }
}
/*
Todo:
1. Check if there are any pending orders before processing any withdrawls/new-trades or orders
2. When cancelling the order, make sure if the order is not partially fullfilled. 
3. Merge the same price orders
4. Enable trading with ETH <-> ERC20
5. Store Fullfilled Trades
6. Cnacel Trades functionality
*/