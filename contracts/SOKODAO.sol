// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

 
contract SOKODAO {
    
    // Product struct
    struct Product {
        uint256 id;
        address seller;
        string name;
        string description;
        string ipfsHash;      // IPFS hash for product images/metadata
        uint256 price;        // Price in wei
        uint256 stock;        // Available quantity
        bool isActive;        // Product availability status
        uint256 createdAt;
    }
    
    // State variables
    uint256 private productCounter;
    mapping(uint256 => Product) public products;
    mapping(address => uint256[]) private sellerProducts;
    
    // Events
    event ProductListed(
        uint256 indexed productId,
        address indexed seller,
        string name,
        uint256 price,
        uint256 stock
    );
    
    event ProductUpdated(
        uint256 indexed productId,
        uint256 price,
        uint256 stock,
        bool isActive
    );
    
    event ProductDeactivated(uint256 indexed productId);
    
    // Modifiers
    modifier onlyProductOwner(uint256 _productId) {
        require(products[_productId].seller == msg.sender, "Not product owner");
        _;
    }
    
    modifier validProduct(uint256 _productId) {
        require(_productId > 0 && _productId <= productCounter, "Invalid product ID");
        _;
    }
    
    function listProduct(
        string memory _name,
        string memory _description,
        string memory _ipfsHash,
        uint256 _price,
        uint256 _stock
    ) external returns (uint256) {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_ipfsHash).length > 0, "IPFS hash required");
        require(_price > 0, "Price must be greater than 0");
        require(_stock > 0, "Stock must be greater than 0");
        
        productCounter++;
        
        products[productCounter] = Product({
            id: productCounter,
            seller: msg.sender,
            name: _name,
            description: _description,
            ipfsHash: _ipfsHash,
            price: _price,
            stock: _stock,
            isActive: true,
            createdAt: block.timestamp
        });
        
        sellerProducts[msg.sender].push(productCounter);
        
        emit ProductListed(productCounter, msg.sender, _name, _price, _stock);
        
        return productCounter;
    }
    
   
    function updateProduct(
        uint256 _productId,
        uint256 _price,
        uint256 _stock
    ) external validProduct(_productId) onlyProductOwner(_productId) {
        require(_price > 0, "Price must be greater than 0");
        
        Product storage product = products[_productId];
        product.price = _price;
        product.stock = _stock;
        
        emit ProductUpdated(_productId, _price, _stock, product.isActive);
    }
    
    function toggleProductStatus(uint256 _productId) 
        external 
        validProduct(_productId) 
        onlyProductOwner(_productId) 
    {
        Product storage product = products[_productId];
        product.isActive = !product.isActive;
        
        if (!product.isActive) {
            emit ProductDeactivated(_productId);
        }
        
        emit ProductUpdated(_productId, product.price, product.stock, product.isActive);
    }
    
    /**
     * @dev Get product details
     * @param _productId Product ID
     */
    function getProduct(uint256 _productId) 
        external 
        view 
        validProduct(_productId) 
        returns (
            uint256 id,
            address seller,
            string memory name,
            string memory description,
            string memory ipfsHash,
            uint256 price,
            uint256 stock,
            bool isActive,
            uint256 createdAt
        ) 
    {
        Product memory product = products[_productId];
        return (
            product.id,
            product.seller,
            product.name,
            product.description,
            product.ipfsHash,
            product.price,
            product.stock,
            product.isActive,
            product.createdAt
        );
    }
    
 
    function getSellerProducts(address _seller) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sellerProducts[_seller];
    }
    
   
    function getTotalProducts() external view returns (uint256) {
        return productCounter;
    }
    

    function _reduceStock(uint256 _productId, uint256 _quantity) 
        internal 
        validProduct(_productId) 
    {
        Product storage product = products[_productId];
        require(product.stock >= _quantity, "Insufficient stock");
        product.stock -= _quantity;
    }
    

    function isProductAvailable(uint256 _productId, uint256 _quantity) 
        external 
        view 
        validProduct(_productId) 
        returns (bool) 
    {
        Product memory product = products[_productId];
        return product.isActive && product.stock >= _quantity;
    }
}
interface IProductListing {
    function getProduct(uint256 _productId) external view returns (
        uint256 id,
        address seller,
        string memory name,
        string memory description,
        string memory ipfsHash,
        uint256 price,
        uint256 stock,
        bool isActive,
        uint256 createdAt
    );
    
    function isProductAvailable(uint256 _productId, uint256 _quantity) external view returns (bool);
}


contract MarketplaceEscrow {
    
    // Order status enum
    enum OrderStatus {
        Pending,        // Payment locked in escrow
        Shipped,        // Seller marked as shipped
        Delivered,      // Buyer confirmed delivery
        Cancelled       // Order cancelled/refunded
    }
    
    // Order struct
    struct Order {
        uint256 orderId;
        uint256 productId;
        address buyer;
        address seller;
        uint256 quantity;
        uint256 totalPrice;
        OrderStatus status;
        uint256 createdAt;
        uint256 deliveredAt;
    }
    
    // State variables
    IProductListing public productListing;
    uint256 private orderCounter;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) private buyerOrders;
    mapping(address => uint256[]) private sellerOrders;
    
    // Platform fee (2.5% = 250 basis points)
    uint256 public platformFee = 250;
    uint256 constant FEE_DENOMINATOR = 10000;
    address public platformWallet;
    
    // Events
    event OrderCreated(
        uint256 indexed orderId,
        uint256 indexed productId,
        address indexed buyer,
        address seller,
        uint256 quantity,
        uint256 totalPrice
    );
    
    event OrderShipped(uint256 indexed orderId);
    event OrderDelivered(uint256 indexed orderId);
    event OrderCancelled(uint256 indexed orderId);
    event FundsReleased(uint256 indexed orderId, address seller, uint256 amount);
    
    // Modifiers
    modifier onlyBuyer(uint256 _orderId) {
        require(orders[_orderId].buyer == msg.sender, "Not the buyer");
        _;
    }
    
    modifier onlySeller(uint256 _orderId) {
        require(orders[_orderId].seller == msg.sender, "Not the seller");
        _;
    }
    
    modifier validOrder(uint256 _orderId) {
        require(_orderId > 0 && _orderId <= orderCounter, "Invalid order ID");
        _;
    }
    
    constructor(address _productListingAddress, address _platformWallet) {
        require(_productListingAddress != address(0), "Invalid product listing address");
        require(_platformWallet != address(0), "Invalid platform wallet");
        productListing = IProductListing(_productListingAddress);
        platformWallet = _platformWallet;
    }
    
   
    function buyProduct(uint256 _productId, uint256 _quantity) 
        external 
        payable 
        returns (uint256) 
    {
        require(_quantity > 0, "Quantity must be greater than 0");
        
        // Get product details from ProductListing contract
        (
            ,
            address seller,
            ,
            ,
            ,
            uint256 price,
            ,
            ,
        ) = productListing.getProduct(_productId);
        
        require(seller != address(0), "Product does not exist");
        require(seller != msg.sender, "Cannot buy your own product");
        
        // Check product availability
        require(
            productListing.isProductAvailable(_productId, _quantity),
            "Product not available"
        );
        
        // Calculate total price
        uint256 totalPrice = price * _quantity;
        require(msg.value == totalPrice, "Incorrect payment amount");
        
        // Create order
        orderCounter++;
        orders[orderCounter] = Order({
            orderId: orderCounter,
            productId: _productId,
            buyer: msg.sender,
            seller: seller,
            quantity: _quantity,
            totalPrice: totalPrice,
            status: OrderStatus.Pending,
            createdAt: block.timestamp,
            deliveredAt: 0
        });
        
        // Track orders
        buyerOrders[msg.sender].push(orderCounter);
        sellerOrders[seller].push(orderCounter);
        
        emit OrderCreated(
            orderCounter,
            _productId,
            msg.sender,
            seller,
            _quantity,
            totalPrice
        );
        
        return orderCounter;
    }
    
    
    function markAsShipped(uint256 _orderId) 
        external 
        validOrder(_orderId)
        onlySeller(_orderId) 
    {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Pending, "Order not in pending state");
        
        order.status = OrderStatus.Shipped;
        
        emit OrderShipped(_orderId);
    }
    
   
    function confirmDelivery(uint256 _orderId) 
        external 
        validOrder(_orderId)
        onlyBuyer(_orderId) 
    {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Shipped, "Order not shipped yet");
        
        order.status = OrderStatus.Delivered;
        order.deliveredAt = block.timestamp;
        
        // Calculate platform fee
        uint256 fee = (order.totalPrice * platformFee) / FEE_DENOMINATOR;
        uint256 sellerAmount = order.totalPrice - fee;
        
        // Transfer funds
        (bool successSeller, ) = payable(order.seller).call{value: sellerAmount}("");
        require(successSeller, "Seller payment failed");
        
        (bool successPlatform, ) = payable(platformWallet).call{value: fee}("");
        require(successPlatform, "Platform fee transfer failed");
        
        emit OrderDelivered(_orderId);
        emit FundsReleased(_orderId, order.seller, sellerAmount);
    }
    
   
    function cancelOrder(uint256 _orderId) 
        external 
        validOrder(_orderId)
        onlyBuyer(_orderId) 
    {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Pending, "Can only cancel pending orders");
        
        order.status = OrderStatus.Cancelled;
        
        // Refund buyer
        (bool success, ) = payable(order.buyer).call{value: order.totalPrice}("");
        require(success, "Refund failed");
        
        emit OrderCancelled(_orderId);
    }
    
    
    function getOrder(uint256 _orderId) 
        external 
        view 
        validOrder(_orderId)
        returns (
            uint256 orderId,
            uint256 productId,
            address buyer,
            address seller,
            uint256 quantity,
            uint256 totalPrice,
            OrderStatus status,
            uint256 createdAt,
            uint256 deliveredAt
        ) 
    {
        Order memory order = orders[_orderId];
        return (
            order.orderId,
            order.productId,
            order.buyer,
            order.seller,
            order.quantity,
            order.totalPrice,
            order.status,
            order.createdAt,
            order.deliveredAt
        );
    }
    
    /**
     * @dev Get all orders for a buyer
     * @param _buyer Buyer address
     */
    function getBuyerOrders(address _buyer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return buyerOrders[_buyer];
    }
    
    /**
     * @dev Get all orders for a seller
     * @param _seller Seller address
     */
    function getSellerOrders(address _seller) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sellerOrders[_seller];
    }
    
    /**
     * @dev Get total number of orders
     */
    function getTotalOrders() external view returns (uint256) {
        return orderCounter;
    }
    
    /**
     * @dev Check order status
     * @param _orderId Order ID
     */
    function getOrderStatus(uint256 _orderId) 
        external 
        view 
        validOrder(_orderId)
        returns (OrderStatus) 
    {
        return orders[_orderId].status;
    }
}