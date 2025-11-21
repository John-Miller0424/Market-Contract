// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Market {
    // ----------- ROLES ----------
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlySeller() {
        require(isSeller[msg.sender], "Not a registered seller");
        _;
    }

    // ----------- SELLER MANAGEMENT ----------
    mapping(address => bool) public isSeller;
    address[] private sellerList;

    event SellerAdded(address seller);
    event SellerRemoved(address seller);

    function addSeller(address seller) external onlyOwner {
        require(seller != address(0), "Invalid address");
        require(!isSeller[seller], "Already seller");

        isSeller[seller] = true;

        // avoid duplicate sellers in sellerList
        bool exists = false;
        for (uint i = 0; i < sellerList.length; i++) {
            if (sellerList[i] == seller) {
                exists = true;
                break;
            }
        }
        if (!exists) sellerList.push(seller);

        emit SellerAdded(seller);
    }

    function removeSeller(address seller) external onlyOwner {
        require(isSeller[seller], "Not a seller");

        isSeller[seller] = false;

        // deactivate all their products
        uint[] storage ids = sellerProducts[seller];
        for (uint i = 0; i < ids.length; i++) {
            uint id = ids[i];
            if (products[id].isActive) {
                products[id].isActive = false;
            }
        }

        emit SellerRemoved(seller);
    }

    function getSellers() external view returns (address[] memory) {
        uint count;
        for (uint i = 0; i < sellerList.length; i++) {
            if (isSeller[sellerList[i]]) count++;
        }

        address[] memory active = new address[](count);
        uint idx;

        for (uint i = 0; i < sellerList.length; i++) {
            if (isSeller[sellerList[i]]) {
                active[idx++] = sellerList[i];
            }
        }

        return active;
    }

    // ----------- PRODUCT SYSTEM WITH ESCROW ----------
    enum ProductStatus { Active, Sold, Completed, Refunded }

    struct Product {
        uint id;
        address seller;
        string name;
        uint price;
        bool isActive;
        ProductStatus status;
    }

    uint public nextProductId;

    mapping(uint => Product) public products;
    mapping(address => uint[]) private sellerProducts;

    event ProductAdded(uint id, address seller, string name, uint price);
    event ProductRemoved(uint id, address seller);

    // add new product
    function addProduct(string calldata name, uint priceWei)
        external
        onlySeller
    {
        require(priceWei > 0, "Price must be > 0");

        nextProductId++;
        uint id = nextProductId;

        products[id] = Product({
            id: id,
            seller: msg.sender,
            name: name,
            price: priceWei,
            isActive: true,
            status: ProductStatus.Active
        });

        sellerProducts[msg.sender].push(id);

        emit ProductAdded(id, msg.sender, name, priceWei);
    }

    function deleteProduct(uint productId) external onlySeller {
        Product storage p = products[productId];
        require(p.seller == msg.sender, "Not your product");
        require(p.isActive, "Already deleted");

        p.isActive = false;

        emit ProductRemoved(productId, msg.sender);
    }

    function getSellerProducts(address seller)
        external
        view
        returns (Product[] memory)
    {
        uint[] storage ids = sellerProducts[seller];

        uint count;
        for (uint i = 0; i < ids.length; i++) {
            if (products[ids[i]].isActive) count++;
        }

        Product[] memory list = new Product[](count);
        uint idx;

        for (uint i = 0; i < ids.length; i++) {
            Product storage p = products[ids[i]];
            if (p.isActive) list[idx++] = p;
        }

        return list;
    }

    function getAllProducts() external view returns (Product[] memory) {
        uint count;
        for (uint id = 1; id <= nextProductId; id++) {
            if (products[id].isActive) count++;
        }

        Product[] memory list = new Product[](count);
        uint idx;

        for (uint id = 1; id <= nextProductId; id++) {
            if (products[id].isActive) {
                list[idx++] = products[id];
            }
        }

        return list;
    }

    // ----------- ESCROW SYSTEM ----------
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

    // BUY PRODUCT (freeze money)
    function buyProduct(uint productId) external payable {
        Product storage p = products[productId];

        require(p.isActive, "Not for sale");
        require(p.status == ProductStatus.Active, "Already sold");
        require(msg.value == p.price, "Incorrect price");

        // freeze money
        escrows[productId] = Escrow({
            buyer: msg.sender,
            amount: msg.value,
            exists: true
        });

        p.status = ProductStatus.Sold;

        buyerPurchases[msg.sender].push(productId);

        emit ProductPurchased(productId, p.seller, msg.sender, p.price);
    }

    // BUYER CONFIRMS DELIVERY → release funds to seller
    function confirmReceived(uint productId) external {
        Escrow storage e = escrows[productId];
        Product storage p = products[productId];

        require(e.exists, "No escrow");
        require(e.buyer == msg.sender, "Not buyer");
        require(p.status == ProductStatus.Sold, "Invalid state");

        payable(p.seller).transfer(e.amount);

        p.status = ProductStatus.Completed;
        p.isActive = false;

        delete escrows[productId];

        emit EscrowReleased(productId);
    }

    // BUYER CLAIMS A PROBLEM (dispute)
    function openDispute(uint productId) external {
        Escrow storage e = escrows[productId];
        require(e.exists, "No escrow");
        require(e.buyer == msg.sender, "Not buyer");
        // freeze but do nothing yet, admin must resolve
    }

    // ADMIN resolves dispute → refund buyer OR pay seller
    function resolveDispute(uint productId, bool refundBuyer) external onlyOwner {
        Escrow storage e = escrows[productId];
        Product storage p = products[productId];
        require(e.exists, "No escrow");

        if (refundBuyer) {
            payable(e.buyer).transfer(e.amount);
            p.status = ProductStatus.Refunded;
        } else {
            payable(p.seller).transfer(e.amount);
            p.status = ProductStatus.Completed;
        }

        p.isActive = false;
        delete escrows[productId];

        if (refundBuyer) emit EscrowRefunded(productId);
        else emit EscrowReleased(productId);
    }

    // BUYER CAN SEE PURCHASE HISTORY
    function getMyPurchases()
        external
        view
        returns (Product[] memory)
    {
        uint[] storage ids = buyerPurchases[msg.sender];
        Product[] memory list = new Product[](ids.length);

        for (uint i = 0; i < ids.length; i++) {
            list[i] = products[ids[i]];
        }

        return list;
    }
}
