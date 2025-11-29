// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VeridyMarketplace
/// @notice A decentralized data marketplace for selling encrypted files stored on IPFS
/// @dev Use ECDH for secure key exchange between sellers and buyers
contract VeridyMarketplace is Ownable {
    IERC20 public usdt;
    bool private _initialized;

    uint256 public listingCount;
    uint256 public purchaseCount;

    /// @notice Represents a data listing created by a seller
    struct DataListing {
        address seller;
        bytes sellerPublicKey; // Seller's ECDH public key for key exchange
        string contentHash; // SHA-256 hash of the original file
        string ipfsCid;
        string title;
        string description;
        string fileType;
        uint256 fileSizeBytes;
        uint256 price; // 6 decimals
        bool isActive;
        bool sold;
        uint256 createdAt;
    }

    /// @notice Status of a purchase
    enum PurchaseStatus {
        None,
        Escrowed,
        Accepted,
        Cancelled
    }

    /// @notice Represents a purchase/order for a data listing
    /// @dev enc_K is populated when seller accepts, enabling buyer to decrypt the file
    struct Purchase {
        address buyer;
        uint256 listingId;
        bytes buyerPublicKey; // Buyer's ECDH public key (compressed or uncompressed)
        bytes32 encK; // ECDH(seller_priv, buyer_pub) encrypted key K
        uint256 amount; // USDT amount in escrow
        uint256 createdAt;
        uint256 acceptedAt; // Timestamp when seller accepted
        PurchaseStatus status;
    }

    /// @notice All listings by ID
    mapping(uint256 => DataListing) public listings;

    /// @notice All purchases by ID
    mapping(uint256 => Purchase) public purchases;

    /// @notice Track active purchase per listing per buyer (listingId => buyer => purchaseId)
    /// @dev Prevents duplicate pending purchases
    mapping(uint256 => mapping(address => uint256)) public activePurchase;

    /// @notice All listing IDs by seller
    mapping(address => uint256[]) public sellerListings;

    /// @notice All purchase IDs by buyer
    mapping(address => uint256[]) public buyerPurchases;

    /// @notice All purchase IDs for a listing
    mapping(uint256 => uint256[]) public listingPurchases;

    event ListingCreated(
        uint256 indexed listingId, address indexed seller, string title, uint256 price, string ipfsCid
    );

    event ListingUpdated(uint256 indexed listingId);
    event ListingDeactivated(uint256 indexed listingId);
    event ListingReactivated(uint256 indexed listingId);

    event PurchaseCreated(uint256 indexed purchaseId, uint256 indexed listingId, address indexed buyer, uint256 amount);

    event PurchaseAccepted(uint256 indexed purchaseId, uint256 indexed listingId, address indexed seller, bytes32 encK);

    event PurchaseCancelled(uint256 indexed purchaseId, uint256 indexed listingId, address indexed buyer);

    error NotSeller();
    error NotBuyer();
    error ListingNotFound();
    error ListingNotActive();
    error PurchaseNotFound();
    error InvalidPrice();
    error InvalidPublicKey();
    error InvalidEncryptedKey();
    error PurchaseAlreadyExists();
    error InvalidPurchaseStatus();
    error TransferFailed();
    error CannotBuyOwnListing();
    error ListingAlreadySold();
    error AlreadyInitialized();
    error NotInitialized();

    /// @notice Deploy the marketplace (must call initialize() after deployment)
    constructor() Ownable(msg.sender) {}

    /// @notice Initialize the marketplace with USDT token address
    /// @dev Can only be called once. Must be called by owner after deployment.
    /// @param _usdt Address of the USDT token contract
    function initialize(address _usdt) external onlyOwner {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        usdt = IERC20(_usdt);
    }

    /// @notice Check if the contract has been initialized
    function initialized() external view returns (bool) {
        return _initialized;
    }

    /// @dev Ensures the contract is initialized before executing
    modifier onlyInitialized() {
        if (!_initialized) revert NotInitialized();
        _;
    }

    /// @notice Create a new data listing
    function createListing(
        bytes calldata _sellerPublicKey,
        string calldata _contentHash,
        string calldata _ipfsCid,
        string calldata _title,
        string calldata _description,
        string calldata _fileType,
        uint256 _fileSizeBytes,
        uint256 _price
    ) external onlyInitialized returns (uint256 listingId) {
        if (_sellerPublicKey.length == 0) revert InvalidPublicKey();
        if (_price == 0) revert InvalidPrice();

        listingId = ++listingCount;

        listings[listingId] = DataListing({
            seller: msg.sender,
            sellerPublicKey: _sellerPublicKey,
            contentHash: _contentHash,
            ipfsCid: _ipfsCid,
            title: _title,
            description: _description,
            fileType: _fileType,
            fileSizeBytes: _fileSizeBytes,
            price: _price,
            isActive: true,
            sold: false,
            createdAt: block.timestamp
        });

        sellerListings[msg.sender].push(listingId);

        emit ListingCreated(listingId, msg.sender, _title, _price, _ipfsCid);
    }

    /// @notice Update an existing listing (only seller can update)
    /// @param _listingId ID of the listing to update
    /// @param _title New title
    /// @param _description New description
    /// @param _price New price in USDT
    function updateListing(uint256 _listingId, string calldata _title, string calldata _description, uint256 _price)
        external
    {
        DataListing storage listing = listings[_listingId];
        if (listing.seller == address(0)) revert ListingNotFound();
        if (listing.seller != msg.sender) revert NotSeller();
        if (_price == 0) revert InvalidPrice();

        listing.title = _title;
        listing.description = _description;
        listing.price = _price;

        emit ListingUpdated(_listingId);
    }

    /// @notice Deactivate a listing (only seller can deactivate)
    /// @param _listingId ID of the listing to deactivate
    function deactivateListing(uint256 _listingId) external {
        DataListing storage listing = listings[_listingId];
        if (listing.seller == address(0)) revert ListingNotFound();
        if (listing.seller != msg.sender) revert NotSeller();

        listing.isActive = false;

        emit ListingDeactivated(_listingId);
    }

    /// @notice Reactivate a listing (only seller can reactivate)
    /// @param _listingId ID of the listing to reactivate
    function reactivateListing(uint256 _listingId) external {
        DataListing storage listing = listings[_listingId];
        if (listing.seller == address(0)) revert ListingNotFound();
        if (listing.seller != msg.sender) revert NotSeller();

        listing.isActive = true;

        emit ListingReactivated(_listingId);
    }

    /// @notice Accept a purchase and provide the encrypted key
    /// @dev The encK is computed off-chain as ECDH(seller_priv, buyer_pub) XOR K
    /// @dev Other pending purchases for this listing will be auto-refunded
    /// @param _purchaseId ID of the purchase to accept
    /// @param _encK The encrypted key K using ECDH shared secret
    function acceptPurchase(uint256 _purchaseId, bytes32 _encK) external onlyInitialized {
        Purchase storage purchase = purchases[_purchaseId];
        if (purchase.buyer == address(0)) revert PurchaseNotFound();
        if (purchase.status != PurchaseStatus.Escrowed) revert InvalidPurchaseStatus();
        if (_encK == bytes32(0)) revert InvalidEncryptedKey();

        uint256 listingId = purchase.listingId;
        DataListing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller();

        // Update purchase status
        purchase.encK = _encK;
        purchase.status = PurchaseStatus.Accepted;
        purchase.acceptedAt = block.timestamp;

        listing.sold = true; // Can only be sold once

        // Clear active purchase tracking for accepted buyer
        activePurchase[listingId][purchase.buyer] = 0;

        // Refund all other pending (escrowed) purchases for this listing
        uint256[] storage purchaseIds = listingPurchases[listingId];
        for (uint256 i = 0; i < purchaseIds.length; i++) {
            uint256 otherPurchaseId = purchaseIds[i];
            if (otherPurchaseId != _purchaseId) {
                Purchase storage otherPurchase = purchases[otherPurchaseId];
                if (otherPurchase.status == PurchaseStatus.Escrowed) {
                    otherPurchase.status = PurchaseStatus.Cancelled;
                    activePurchase[listingId][otherPurchase.buyer] = 0;

                    // Refund the buyer
                    bool refundSuccess = usdt.transfer(otherPurchase.buyer, otherPurchase.amount);
                    if (!refundSuccess) revert TransferFailed();

                    emit PurchaseCancelled(otherPurchaseId, listingId, otherPurchase.buyer);
                }
            }
        }

        // Transfer USDT from escrow to seller
        bool success = usdt.transfer(listing.seller, purchase.amount);
        if (!success) revert TransferFailed();

        emit PurchaseAccepted(_purchaseId, listingId, msg.sender, _encK);
    }

    /// @notice Purchase a listing by putting USDT in escrow
    /// @dev Buyer must approve this contract to spend USDT first
    /// @param _listingId ID of the listing to purchase
    /// @param _buyerPublicKey Buyer's ECDH public key for key exchange
    /// @return purchaseId The ID of the created purchase
    function purchaseListing(uint256 _listingId, bytes calldata _buyerPublicKey)
        external
        onlyInitialized
        returns (uint256 purchaseId)
    {
        DataListing storage listing = listings[_listingId];
        if (listing.seller == address(0)) revert ListingNotFound();
        if (!listing.isActive) revert ListingNotActive();
        if (listing.sold) revert ListingAlreadySold();
        if (listing.seller == msg.sender) revert CannotBuyOwnListing();
        if (_buyerPublicKey.length == 0) revert InvalidPublicKey();

        // Check if buyer already has an active purchase for this listing
        if (activePurchase[_listingId][msg.sender] != 0) revert PurchaseAlreadyExists();

        purchaseId = ++purchaseCount;

        purchases[purchaseId] = Purchase({
            buyer: msg.sender,
            listingId: _listingId,
            buyerPublicKey: _buyerPublicKey,
            encK: bytes32(0),
            amount: listing.price,
            createdAt: block.timestamp,
            acceptedAt: 0,
            status: PurchaseStatus.Escrowed
        });

        // Track active purchase
        activePurchase[_listingId][msg.sender] = purchaseId;
        buyerPurchases[msg.sender].push(purchaseId);
        listingPurchases[_listingId].push(purchaseId);

        // Transfer USDT to escrow (this contract)
        bool success = usdt.transferFrom(msg.sender, address(this), listing.price);
        if (!success) revert TransferFailed();

        emit PurchaseCreated(purchaseId, _listingId, msg.sender, listing.price);
    }

    /// @notice Cancel a purchase and get refund (only while in escrow)
    /// @param _purchaseId ID of the purchase to cancel
    function cancelPurchase(uint256 _purchaseId) external onlyInitialized {
        Purchase storage purchase = purchases[_purchaseId];
        if (purchase.buyer == address(0)) revert PurchaseNotFound();
        if (purchase.buyer != msg.sender) revert NotBuyer();
        if (purchase.status != PurchaseStatus.Escrowed) revert InvalidPurchaseStatus();

        purchase.status = PurchaseStatus.Cancelled;

        // Clear active purchase tracking
        activePurchase[purchase.listingId][msg.sender] = 0;

        // Refund USDT to buyer
        bool success = usdt.transfer(msg.sender, purchase.amount);
        if (!success) revert TransferFailed();

        emit PurchaseCancelled(_purchaseId, purchase.listingId, msg.sender);
    }

    // --- view funcs ---

    /// @notice Get a listing by ID
    /// @param _listingId ID of the listing
    /// @return The DataListing struct
    function getListing(uint256 _listingId) external view returns (DataListing memory) {
        return listings[_listingId];
    }

    /// @notice Get a purchase by ID
    /// @param _purchaseId ID of the purchase
    /// @return The Purchase struct
    function getPurchase(uint256 _purchaseId) external view returns (Purchase memory) {
        return purchases[_purchaseId];
    }

    /// @notice Get all listings with pagination
    /// @param _offset Starting index (1-based listing IDs)
    /// @param _limit Maximum number of listings to return
    /// @return listingIds Array of listing IDs
    /// @return dataListings Array of DataListing structs
    function getListings(uint256 _offset, uint256 _limit)
        external
        view
        returns (uint256[] memory listingIds, DataListing[] memory dataListings)
    {
        if (_offset == 0) _offset = 1;
        if (_offset > listingCount) {
            return (new uint256[](0), new DataListing[](0));
        }

        uint256 end = _offset + _limit;
        if (end > listingCount + 1) end = listingCount + 1;
        uint256 count = end - _offset;

        listingIds = new uint256[](count);
        dataListings = new DataListing[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 id = _offset + i;
            listingIds[i] = id;
            dataListings[i] = listings[id];
        }
    }

    /// @notice Get only active listings with pagination
    /// @param _offset Starting index for iteration
    /// @param _limit Maximum number of active listings to return
    /// @return listingIds Array of active listing IDs
    /// @return dataListings Array of active DataListing structs
    function getActiveListings(uint256 _offset, uint256 _limit)
        external
        view
        returns (uint256[] memory listingIds, DataListing[] memory dataListings)
    {
        uint256 startId = _offset == 0 ? 1 : _offset;

        // Find active listings
        uint256[] memory tempIds = new uint256[](_limit);
        uint256 found = 0;

        for (uint256 id = startId; id <= listingCount && found < _limit; id++) {
            if (listings[id].isActive) {
                tempIds[found] = id;
                found++;
            }
        }

        // Create correctly sized arrays
        listingIds = new uint256[](found);
        dataListings = new DataListing[](found);

        for (uint256 i = 0; i < found; i++) {
            listingIds[i] = tempIds[i];
            dataListings[i] = listings[tempIds[i]];
        }
    }

    /// @notice Get all listings by a seller
    /// @param _seller Address of the seller
    /// @return listingIds Array of listing IDs
    /// @return dataListings Array of DataListing structs
    function getListingsBySeller(address _seller)
        external
        view
        returns (uint256[] memory listingIds, DataListing[] memory dataListings)
    {
        listingIds = sellerListings[_seller];
        dataListings = new DataListing[](listingIds.length);

        for (uint256 i = 0; i < listingIds.length; i++) {
            dataListings[i] = listings[listingIds[i]];
        }
    }

    /// @notice Get all purchases by a buyer
    /// @param _buyer Address of the buyer
    /// @return purchaseIds Array of purchase IDs
    /// @return purchaseData Array of Purchase structs
    function getPurchasesByBuyer(address _buyer)
        external
        view
        returns (uint256[] memory purchaseIds, Purchase[] memory purchaseData)
    {
        purchaseIds = buyerPurchases[_buyer];
        purchaseData = new Purchase[](purchaseIds.length);

        for (uint256 i = 0; i < purchaseIds.length; i++) {
            purchaseData[i] = purchases[purchaseIds[i]];
        }
    }

    /// @notice Get all purchases for a listing
    /// @param _listingId ID of the listing
    /// @return purchaseIds Array of purchase IDs
    /// @return purchaseData Array of Purchase structs
    function getPurchasesForListing(uint256 _listingId)
        external
        view
        returns (uint256[] memory purchaseIds, Purchase[] memory purchaseData)
    {
        purchaseIds = listingPurchases[_listingId];
        purchaseData = new Purchase[](purchaseIds.length);

        for (uint256 i = 0; i < purchaseIds.length; i++) {
            purchaseData[i] = purchases[purchaseIds[i]];
        }
    }

    /// @notice Get pending (escrowed) purchases for a seller to accept
    /// @param _seller Address of the seller
    /// @return purchaseIds Array of pending purchase IDs
    /// @return purchaseData Array of pending Purchase structs
    function getPendingPurchasesForSeller(address _seller)
        external
        view
        returns (uint256[] memory purchaseIds, Purchase[] memory purchaseData)
    {
        uint256[] memory sellerListingIds = sellerListings[_seller];

        // first pass: count pending purchases
        uint256 pendingCount = 0;
        for (uint256 i = 0; i < sellerListingIds.length; i++) {
            uint256[] memory listingPurchaseIds = listingPurchases[sellerListingIds[i]];
            for (uint256 j = 0; j < listingPurchaseIds.length; j++) {
                if (purchases[listingPurchaseIds[j]].status == PurchaseStatus.Escrowed) {
                    pendingCount++;
                }
            }
        }

        // second pass: collect pending purchases
        purchaseIds = new uint256[](pendingCount);
        purchaseData = new Purchase[](pendingCount);
        uint256 index = 0;

        for (uint256 i = 0; i < sellerListingIds.length; i++) {
            uint256[] memory listingPurchaseIds = listingPurchases[sellerListingIds[i]];
            for (uint256 j = 0; j < listingPurchaseIds.length; j++) {
                Purchase storage purchase = purchases[listingPurchaseIds[j]];
                if (purchase.status == PurchaseStatus.Escrowed) {
                    purchaseIds[index] = listingPurchaseIds[j];
                    purchaseData[index] = purchase;
                    index++;
                }
            }
        }
    }

    /// @notice Get completed purchases for a buyer (with enc_K for decryption)
    /// @param _buyer Address of the buyer
    /// @return purchaseIds Array of completed purchase IDs
    /// @return purchaseData Array of completed Purchase structs
    function getCompletedPurchasesByBuyer(address _buyer)
        external
        view
        returns (uint256[] memory purchaseIds, Purchase[] memory purchaseData)
    {
        uint256[] memory allPurchaseIds = buyerPurchases[_buyer];

        // first pass: count completed purchases
        uint256 completedCount = 0;
        for (uint256 i = 0; i < allPurchaseIds.length; i++) {
            if (purchases[allPurchaseIds[i]].status == PurchaseStatus.Accepted) {
                completedCount++;
            }
        }

        // second pass: collect completed purchases
        purchaseIds = new uint256[](completedCount);
        purchaseData = new Purchase[](completedCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allPurchaseIds.length; i++) {
            Purchase storage purchase = purchases[allPurchaseIds[i]];
            if (purchase.status == PurchaseStatus.Accepted) {
                purchaseIds[index] = allPurchaseIds[i];
                purchaseData[index] = purchase;
                index++;
            }
        }
    }

    /// @notice Get the total number of listings
    /// @return Total listing count
    function getTotalListings() external view returns (uint256) {
        return listingCount;
    }

    /// @notice Get the total number of purchases
    /// @return Total purchase count
    function getTotalPurchases() external view returns (uint256) {
        return purchaseCount;
    }

    /// @notice Check if a buyer has already purchased a specific listing
    /// @param _listingId ID of the listing
    /// @param _buyer Address of the buyer
    /// @return hasAccepted Whether the buyer has a completed purchase for this listing
    /// @return purchaseId The purchase ID if exists, 0 otherwise
    function hasBuyerPurchasedListing(uint256 _listingId, address _buyer)
        external
        view
        returns (bool hasAccepted, uint256 purchaseId)
    {
        uint256[] memory buyerPurchaseIds = buyerPurchases[_buyer];

        for (uint256 i = 0; i < buyerPurchaseIds.length; i++) {
            Purchase storage purchase = purchases[buyerPurchaseIds[i]];
            if (purchase.listingId == _listingId && purchase.status == PurchaseStatus.Accepted) {
                return (true, buyerPurchaseIds[i]);
            }
        }

        return (false, 0);
    }
}

