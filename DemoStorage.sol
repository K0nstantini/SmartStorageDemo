// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
Первый проект на Solidity и в целом знакомство с сетью Ethereum.
Не писал тесты (не знаком с фреймворками и js, что заняло бы прилично времени), соответственно что-то можно лучше оптимизировать
Не реализовано сохранение транзакций при вызове метода `updateBalance`, но в задании это и не указано и, как я понимаю, это в целом дорогое удовольствие.

Расход газа:
- saveRecord():    ~75000
- updateBalance(): ~28000

My Ethereum addr: 0x93453dE2aeA091FAE1fDB7ae5D8cD44BB1Bbb56D
*/

contract DemoStorage {
    uint lastUid = 0;
    
    struct Record {
        bytes32 data;             // store balance, birthdate, sex, name
        bytes32 addressTimestamp; // store address and timestamp
    }

    mapping(uint => Record) records;

    function saveRecord(string memory name, bool sex, uint64 sum, uint16 y, uint8 m, uint8 d) public returns(uint) {
        bytes32 byteName;
        assembly {
            byteName := mload(add(name, 32))     
        }
        checkRecordFields(block.timestamp, byteName, sum, y, m, d);

        bytes32 data;
        bytes32 ad;
        address sender = msg.sender;

        assembly {
            // first bytes32: balance: 5 bytes, sex: 1 byte, year: 2 bytes, (m, d): 1 byte, name: 22 bytes
            mstore(0x2A, byteName)
            mstore(0xA, y)   // year
            mstore(0x8, m)   // month
            mstore(0x7, d)   // day
            mstore(0x6, sex) // sex == true => "man"), whole 1 byte, but it can be 1 bit for example in 'year' field and give this byte to the balance or name
            mstore(0x5, sum) // balance, assume that the balance cannot be less than 0. Can increase if 5 byte is not enough
            data := mload(0x20)

            // second bytes32: empty (we can put something here): 8 bytes , address: 20 byte, timestamp: 4 bytes
            mstore(0x20, timestamp())
            mstore(0x1C, sender)
            ad := mload(0x20)
        }

        records[++lastUid] = Record(data, ad);
        return lastUid;
    }

    // not very optimized, as it does not consume gas
    function showRecord(uint uid) public view returns (string memory name, uint64 b, uint duration, uint age, address ad) {   
        Record memory rec =  records[uid];
        bytes32 data = rec.data;
        require(data != 0, "invalid id");
        bytes32 addAndTime = rec.addressTimestamp;
           
        bytes32 bName;
        bool sex;
        uint32 time;
        uint16 y;      
        uint8 m;
        uint8 d;

        assembly {
            mstore(0x20, data)
            bName := mload(0x2A)
            y := mload(0xA)
            m := mload(0x8)
            d := mload(0x7)
            sex := shr(248, mload(0x25))
            b := div(shr(216, data), 100) // just dropped cents (the task specifies to show the balance in euros), but it may be necessary to specify a fractional part

            time := addAndTime
            mstore(0x20, addAndTime)
            ad := mload(0x1C)
        }
        ad = address(ad);        
        name = string(abi.encodePacked(sex? "Mr. " : "Ms. ", bytes32ToString2(bName)));
        (age, duration) = getAge(time, y, m, d);
    }

    // int128 because we only have 5 bytes for balance
    // may be add an operation param and amount as `uint` (a little cheaper if op. `expense`)
    function updateBalance(uint uid, int128 amount) public returns(uint sum) {
        bytes32 data = records[uid].data;
        require(data != 0, "invalid id");

        bool notEnoughBalance;
        assembly {
            sum := shr(216, data)

            switch sgt(amount, 0)            
            case true {                
                sum := add(sum, amount)
            }
            case false {
                amount := add(not(amount), 1)
                switch lt(sum, amount)
                case true {
                    notEnoughBalance := true
                }
                case false {
                    sum := sub(sum, amount)
                }
            }
        }
        require(sum < 1099511627776, "too large amount");
        require(!notEnoughBalance, "not enough balance");

        assembly {
            mstore(0x20, data)
            mstore(0x5, sum)
            data := mload(0x20)
        }

        records[uid].data = data;
    }

    function checkRecordFields(uint tstamp, bytes32 byteName, uint64 sum, uint16 y, uint8 m, uint8 d) private pure {
        bool correctName;        
        assembly {
            correctName := gt(byteName, 0)            
        }
        require(correctName, "empty name");

        assembly {
            correctName := eq(byteName, and(byteName, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000)) // no more than 22 bytes
        }
        require(correctName, "too long name");
        
        uint128 daysInMonth;
        uint128 maxYear;

        // may be better to check at a lower level or made some hardcode in contract, but not sure if it's worth it
        if (m == 4 || m == 6 || m == 9 || m == 11) {
            daysInMonth = 30;            
        } else if (m == 2) {
            daysInMonth = ((y % 4 == 0) && (y % 100 != 0)) || (y % 400 == 0) ? 29 : 28;
        } else {
            daysInMonth = 31;            
        }

        // the year check is pretty rough        
        assembly {
            maxYear := add(1970, div(tstamp, 31556926)) // div in asm cheaper
        }        
        require(y > 1920 && y < maxYear && m > 0 && m < 13 && d > 0 && d <= daysInMonth, "invalid birthdate");

        require(sum < 1099511627776, "too large amount on balance");
    }

    function bytes32ToString2(bytes32 _bytes32) private pure returns (string memory) {
        bytes memory bytesArray = new bytes(32);
        for (uint256 i; i < 32; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function daysToDate(uint _days) private pure returns (uint y, uint m, uint d) {
        uint L = _days + 68569 + 2440588;
        uint N = (4 * L) / 146097;
        L = L - (146097 * N + 3) / 4;
        y = (4000 * (L + 1)) / 1461001;
        L = L - (1461 * y) / 4 + 31;
        m = (80 * L) / 2447;
        d = L - (2447 * m) / 80;
        L = m / 11;
        m = m + 2 - 12 * L;
        y = 100 * (N - 49) + y + L;
    }

    function getAge(uint32 registerTime, uint16 _y, uint8 _m, uint8 _d) private view returns (uint age, uint duration) {
        uint timestamp = block.timestamp;
        uint y; 
        uint m; 
        uint d;
        (y, m, d) = daysToDate(timestamp / 86400);
        uint off = (m > _m|| m == _m && d >= _d)? 0 : 1;
        age = y - _y - off;
        duration = (timestamp - registerTime) / 86400;
    }

}