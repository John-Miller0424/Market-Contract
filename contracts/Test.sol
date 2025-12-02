// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Test {
    address public owner;

    constructor (address _owner) {
        owner = _owner;
    }

    modifier onlyOwner () {
        require(msg.sender == owner, "Not Owner");
        _;
    }

    modifier onlySeller () {
        require(isSeller[msg.sender], "Not a registered Seller");
        _;
    }

    mapping(address => bool) public isSeller;
    address[] private sellerList;

    event SellerAdded (address seller);
    event SellerRemoved (address seller);

    function addSeller(address seller) external onlyOwner {
        require(seller != address(0), "Invalid address");
        require(!isSeller[seller], "Already existed");

        isSeller[seller] = true;

        bool exists = false;
        for(uint i=0; i< sellerList.length; i++) {
            if(sellerList[i] == seller) {
                exists = true;
                break;
            }
        }
        if(!exists) sellerList.push(seller);

        emit SellerAdded(seller);
    }

    function removeSeller(address seller) external onlyOwner {
        require(isSeller[seller], "Not Seller");

        isSeller[seller] = false;

        uint[] storage idx = sellerProducts[seller];
        for(uint i=0; i< idx.length; i++) {
            uint id = idx[i];
            if(products[id].isActive)
                products[id].isActive = false;
        }

        emit SellerRemoved(seller);
    }

    function getSellers() external view returns (address[] memory) {
        uint count;
        for(uint i = 0; i < sellerList.length; i++) {
            if( isSeller[sellerList[i]]) count++;
        }

        address[] memory temp = new address[](count);
        uint idx;
        for(uint i = 0; i < sellerList.length; i++) {
            if (isSeller[sellerList[i]]) {
                temp[idx++] = sellerList[i];
            }
        }
        return temp;
    }

    enum ProductStatus {Active, Sold, Completed, Rejected }
    struct Product {
        uint id;
        address seller;
        string name;
        uint price;
        bool isActive;
        ProductStatus status;
    }
    uint productIdx;

    mapping(uint => Product) public products;
    mapping (address => uint[]) private sellerProducts;

    event ProductAdded(uint id, address seller, string name, uint price);
    event ProductDeleted(uint id, address seller);

    function addProduct(string calldata name, uint priceWei) external onlySeller {
        require(priceWei > 0, "Price is not correct");

        productIdx ++;
        products[productIdx] = Product({
            id: productIdx,
            seller: msg.sender,
            name: name,
            price: priceWei,
            isActive: true,
            status: ProductStatus.Active
        });

        sellerProducts[msg.sender].push(productIdx);

        emit ProductAdded(productIdx, msg.sender, name, priceWei);
    }

    function deleteProduct(uint productId) external onlySeller {
        Product storage p = products[productId];
        require(p.seller == msg.sender, "Not your product");
        require(p.isActive, "Already deleted");

        p.isActive = false;

        emit ProductDeleted(productId, msg.sender);
    }

    function getSellerProducts(address seller) external view returns (Product[] memory) {
        uint count;
        uint[] storage idx = sellerProducts[seller];

        for (uint i=0; i< idx.length; i++) {
            if(products[idx[i]].isActive) count++;
        }

        Product[] memory temp = new Product[](count);
        uint cnt;

        for (uint i=0; i< idx.length; i++) {
            Product storage p = products[idx[i]];
            if(p.isActive) temp[cnt++] = p;
        }

        return temp;
    }

    function getAllProducts() external view returns (Product[] memory) {
        uint count;
        
        for( uint i=1; i <= productIdx; i++) {
            if(products[i].isActive) count++;
        }

        Product[] memory temp = new Product[](count);
        uint cnt;

        for(uint i=1; i<= productIdx; i++) {
            if(products[i].isActive) {
                temp[cnt++] = products[i];
            }
        }
        return temp;
    }

    struct Escrow {
        address buyer;
        uint amount;
        bool exists;
    }

    mapping(uint => Escrow) public escrows;
    mapping(address => uint[]) private buyerPurchases; 

    event ProductPurchased(uint id, address seller, address buyer, uint price);
    event EscrowReleased(uint id);
    event EscrowRefunded(uint id);

    function buyProduct(uint id) external payable {
        Product storage p = products[id];

        require(p.isActive, "Not for Sale");
        require(p.status == ProductStatus.Active, "Already Sold");
        require(p.price == msg.value, "The price is not correct");

        escrows[id] = Escrow ({
            buyer: msg.sender,
            amount: msg.value,
            exists: true
        });

        p.status = ProductStatus.Sold;
        buyerPurchases[msg.sender].push(id);

        emit ProductPurchased(id, p.seller, msg.sender, p.price);
    }

    function confirmReceived(uint id) external {
        Escrow storage e = escrows[id];
        Product storage p = products[id];

        require(e.exists, "Not in Escrow");
        require(e.buyer == msg.sender, "Not Buyer");
        require(p.status == ProductStatus.Sold, "Invalid State");

        payable(p.seller).transfer(e.amount);

        p.status = ProductStatus.Completed;
        p.isActive = false;
        
        delete escrows[id];

        emit EscrowReleased(id);
    }

    function resolveDispute(uint id, bool refundBuyer) external onlyOwner {
        Escrow storage e = escrows[id];
        Product storage p = products[id];

        require(e.exists, "Not in Escrow");

        if(refundBuyer) {
            payable(e.buyer).transfer(e.amount);
        } else {
            payable(p.seller).transfer(e.amount);
        }

        p.isActive = false;
        delete escrows[id];

        if(refundBuyer) emit EscrowRefunded(id);
        else emit EscrowReleased(id);
    }

    function getMyPurchases() external view returns (Product[] memory) {
        uint[] storage ids = buyerPurchases[msg.sender];

        Product[] memory temp = new Product[](ids.length);

        for (uint i = 0; i < ids.length; i++) {
            temp[i] = products[ids[i]];
        }

        return temp;
    }
}