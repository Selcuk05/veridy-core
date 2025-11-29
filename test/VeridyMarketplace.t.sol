// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VeridyMarketplace} from "../src/VeridyMarketplace.sol";
import {MockUSDT} from "./mocks/MockUSDT.sol";

contract VeridyMarketplaceTest is Test {
    VeridyMarketplace public marketplace;
    MockUSDT public usdt;

    address public owner;
    address public seller;
    address public buyer1;
    address public buyer2;
    address public buyer3;

    uint256 public constant LISTING_PRICE = 100 * 1e6;
    bytes public constant SELLER_PUBLIC_KEY =
        hex"04fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fe";
    bytes public constant BUYER_PUBLIC_KEY =
        hex"04abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab";
    bytes32 public constant ENC_K = keccak256("encrypted_key");

    event ListingCreated(
        uint256 indexed listingId, address indexed seller, string title, uint256 price, string ipfsCid
    );
    event ListingUpdated(uint256 indexed listingId);
    event ListingDeactivated(uint256 indexed listingId);
    event ListingReactivated(uint256 indexed listingId);
    event PurchaseCreated(uint256 indexed purchaseId, uint256 indexed listingId, address indexed buyer, uint256 amount);
    event PurchaseAccepted(uint256 indexed purchaseId, uint256 indexed listingId, address indexed seller, bytes32 encK);
    event PurchaseCancelled(uint256 indexed purchaseId, uint256 indexed listingId, address indexed buyer);

    function setUp() public {
        owner = address(this);
        seller = makeAddr("seller");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        buyer3 = makeAddr("buyer3");

        usdt = new MockUSDT();

        marketplace = new VeridyMarketplace();

        marketplace.initialize(address(usdt));

        usdt.mint(buyer1, 1000 * 1e6);
        usdt.mint(buyer2, 1000 * 1e6);
        usdt.mint(buyer3, 1000 * 1e6);

        vm.prank(buyer1);
        usdt.approve(address(marketplace), type(uint256).max);
        vm.prank(buyer2);
        usdt.approve(address(marketplace), type(uint256).max);
        vm.prank(buyer3);
        usdt.approve(address(marketplace), type(uint256).max);
    }

    function _createListing() internal returns (uint256 listingId) {
        vm.prank(seller);
        listingId = marketplace.createListing(
            SELLER_PUBLIC_KEY,
            "QmContentHash123",
            "QmTestCid123",
            "Test Dataset",
            "A test dataset for unit testing",
            "csv",
            1024000,
            LISTING_PRICE
        );
    }

    function _purchaseListing(uint256 listingId, address buyer) internal returns (uint256 purchaseId) {
        vm.prank(buyer);
        purchaseId = marketplace.purchaseListing(listingId, BUYER_PUBLIC_KEY);
    }

    function test_Constructor() public view {
        assertEq(address(marketplace.usdt()), address(usdt));
        assertEq(marketplace.owner(), owner);
        assertEq(marketplace.listingCount(), 0);
        assertEq(marketplace.purchaseCount(), 0);
        assertTrue(marketplace.initialized());
    }

    function test_Initialize_RevertAlreadyInitialized() public {
        vm.expectRevert(VeridyMarketplace.AlreadyInitialized.selector);
        marketplace.initialize(address(usdt));
    }

    function test_Initialize_RevertNotOwner() public {
        VeridyMarketplace newMarketplace = new VeridyMarketplace();

        vm.prank(seller);
        vm.expectRevert();
        newMarketplace.initialize(address(usdt));
    }

    function test_NotInitialized_RevertOnCreateListing() public {
        VeridyMarketplace uninitializedMarketplace = new VeridyMarketplace();

        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.NotInitialized.selector);
        uninitializedMarketplace.createListing(
            SELLER_PUBLIC_KEY, "hash", "QmCid", "title", "desc", "csv", 1000, 100 * 1e6
        );
    }

    function test_CreateListing() public {
        vm.expectEmit(true, true, false, true);
        emit ListingCreated(1, seller, "Test Dataset", LISTING_PRICE, "QmTestCid123");

        uint256 listingId = _createListing();

        assertEq(listingId, 1);
        assertEq(marketplace.listingCount(), 1);

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.sellerPublicKey, SELLER_PUBLIC_KEY);
        assertEq(listing.contentHash, "QmContentHash123");
        assertEq(listing.ipfsCid, "QmTestCid123");
        assertEq(listing.title, "Test Dataset");
        assertEq(listing.description, "A test dataset for unit testing");
        assertEq(listing.fileType, "csv");
        assertEq(listing.fileSizeBytes, 1024000);
        assertEq(listing.price, LISTING_PRICE);
        assertTrue(listing.isActive);
        assertFalse(listing.sold);
        assertGt(listing.createdAt, 0);
    }

    function test_CreateListing_MultipleListings() public {
        uint256 listingId1 = _createListing();
        uint256 listingId2 = _createListing();
        uint256 listingId3 = _createListing();

        assertEq(listingId1, 1);
        assertEq(listingId2, 2);
        assertEq(listingId3, 3);
        assertEq(marketplace.listingCount(), 3);
    }

    function test_CreateListing_RevertZeroPrice() public {
        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.InvalidPrice.selector);
        marketplace.createListing(SELLER_PUBLIC_KEY, "hash", "QmCid", "title", "desc", "csv", 1000, 0);
    }

    function test_UpdateListing() public {
        uint256 listingId = _createListing();

        vm.expectEmit(true, false, false, false);
        emit ListingUpdated(listingId);

        vm.prank(seller);
        marketplace.updateListing(listingId, "Updated Title", "Updated Description", 200 * 1e6);

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertEq(listing.title, "Updated Title");
        assertEq(listing.description, "Updated Description");
        assertEq(listing.price, 200 * 1e6);
    }

    function test_UpdateListing_RevertNotSeller() public {
        uint256 listingId = _createListing();

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.NotSeller.selector);
        marketplace.updateListing(listingId, "New Title", "New Desc", 200 * 1e6);
    }

    function test_UpdateListing_RevertListingNotFound() public {
        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.ListingNotFound.selector);
        marketplace.updateListing(999, "Title", "Desc", 100 * 1e6);
    }

    function test_UpdateListing_RevertZeroPrice() public {
        uint256 listingId = _createListing();

        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.InvalidPrice.selector);
        marketplace.updateListing(listingId, "Title", "Desc", 0);
    }

    function test_DeactivateListing() public {
        uint256 listingId = _createListing();

        vm.expectEmit(true, false, false, false);
        emit ListingDeactivated(listingId);

        vm.prank(seller);
        marketplace.deactivateListing(listingId);

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertFalse(listing.isActive);
    }

    function test_DeactivateListing_RevertNotSeller() public {
        uint256 listingId = _createListing();

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.NotSeller.selector);
        marketplace.deactivateListing(listingId);
    }

    function test_DeactivateListing_RevertListingNotFound() public {
        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.ListingNotFound.selector);
        marketplace.deactivateListing(999);
    }

    function test_ReactivateListing() public {
        uint256 listingId = _createListing();

        vm.prank(seller);
        marketplace.deactivateListing(listingId);

        vm.expectEmit(true, false, false, false);
        emit ListingReactivated(listingId);

        vm.prank(seller);
        marketplace.reactivateListing(listingId);

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertTrue(listing.isActive);
    }

    function test_ReactivateListing_RevertNotSeller() public {
        uint256 listingId = _createListing();

        vm.prank(seller);
        marketplace.deactivateListing(listingId);

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.NotSeller.selector);
        marketplace.reactivateListing(listingId);
    }

    function test_ReactivateListing_RevertListingNotFound() public {
        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.ListingNotFound.selector);
        marketplace.reactivateListing(999);
    }

    function test_PurchaseListing() public {
        uint256 listingId = _createListing();
        uint256 buyer1BalanceBefore = usdt.balanceOf(buyer1);

        vm.expectEmit(true, true, true, true);
        emit PurchaseCreated(1, listingId, buyer1, LISTING_PRICE);

        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        assertEq(purchaseId, 1);
        assertEq(marketplace.purchaseCount(), 1);
        assertEq(usdt.balanceOf(buyer1), buyer1BalanceBefore - LISTING_PRICE);
        assertEq(usdt.balanceOf(address(marketplace)), LISTING_PRICE);

        VeridyMarketplace.Purchase memory purchase = marketplace.getPurchase(purchaseId);
        assertEq(purchase.buyer, buyer1);
        assertEq(purchase.listingId, listingId);
        assertEq(purchase.buyerPublicKey, BUYER_PUBLIC_KEY);
        assertEq(purchase.encK, bytes32(0));
        assertEq(purchase.amount, LISTING_PRICE);
        assertGt(purchase.createdAt, 0);
        assertEq(purchase.acceptedAt, 0);
        assertEq(uint256(purchase.status), uint256(VeridyMarketplace.PurchaseStatus.Escrowed));
    }

    function test_PurchaseListing_RevertListingNotFound() public {
        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.ListingNotFound.selector);
        marketplace.purchaseListing(999, BUYER_PUBLIC_KEY);
    }

    function test_PurchaseListing_RevertListingNotActive() public {
        uint256 listingId = _createListing();

        vm.prank(seller);
        marketplace.deactivateListing(listingId);

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.ListingNotActive.selector);
        marketplace.purchaseListing(listingId, BUYER_PUBLIC_KEY);
    }

    function test_PurchaseListing_RevertListingAlreadySold() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId, ENC_K);

        vm.prank(buyer2);
        vm.expectRevert(VeridyMarketplace.ListingAlreadySold.selector);
        marketplace.purchaseListing(listingId, BUYER_PUBLIC_KEY);
    }

    function test_PurchaseListing_RevertCannotBuyOwnListing() public {
        uint256 listingId = _createListing();

        usdt.mint(seller, 1000 * 1e6);
        vm.prank(seller);
        usdt.approve(address(marketplace), type(uint256).max);

        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.CannotBuyOwnListing.selector);
        marketplace.purchaseListing(listingId, BUYER_PUBLIC_KEY);
    }

    function test_PurchaseListing_RevertInvalidPublicKey() public {
        uint256 listingId = _createListing();

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.InvalidPublicKey.selector);
        marketplace.purchaseListing(listingId, "");
    }

    function test_PurchaseListing_RevertPurchaseAlreadyExists() public {
        uint256 listingId = _createListing();

        _purchaseListing(listingId, buyer1);

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.PurchaseAlreadyExists.selector);
        marketplace.purchaseListing(listingId, BUYER_PUBLIC_KEY);
    }

    function test_PurchaseListing_MultipleBuyers() public {
        uint256 listingId = _createListing();

        uint256 purchaseId1 = _purchaseListing(listingId, buyer1);
        uint256 purchaseId2 = _purchaseListing(listingId, buyer2);
        uint256 purchaseId3 = _purchaseListing(listingId, buyer3);

        assertEq(purchaseId1, 1);
        assertEq(purchaseId2, 2);
        assertEq(purchaseId3, 3);
        assertEq(marketplace.purchaseCount(), 3);
        assertEq(usdt.balanceOf(address(marketplace)), LISTING_PRICE * 3);
    }

    function test_AcceptPurchase() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);
        uint256 sellerBalanceBefore = usdt.balanceOf(seller);

        vm.expectEmit(true, true, true, true);
        emit PurchaseAccepted(purchaseId, listingId, seller, ENC_K);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId, ENC_K);

        assertEq(usdt.balanceOf(seller), sellerBalanceBefore + LISTING_PRICE);
        assertEq(usdt.balanceOf(address(marketplace)), 0);

        VeridyMarketplace.Purchase memory purchase = marketplace.getPurchase(purchaseId);
        assertEq(purchase.encK, ENC_K);
        assertEq(uint256(purchase.status), uint256(VeridyMarketplace.PurchaseStatus.Accepted));
        assertGt(purchase.acceptedAt, 0);

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertTrue(listing.sold);
    }

    function test_AcceptPurchase_RevertPurchaseNotFound() public {
        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.PurchaseNotFound.selector);
        marketplace.acceptPurchase(999, ENC_K);
    }

    function test_AcceptPurchase_RevertInvalidPurchaseStatus() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId, ENC_K);

        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.InvalidPurchaseStatus.selector);
        marketplace.acceptPurchase(purchaseId, ENC_K);
    }

    function test_AcceptPurchase_RevertInvalidEncryptedKey() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        vm.prank(seller);
        vm.expectRevert(VeridyMarketplace.InvalidEncryptedKey.selector);
        marketplace.acceptPurchase(purchaseId, bytes32(0));
    }

    function test_AcceptPurchase_RevertNotSeller() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        vm.prank(buyer2);
        vm.expectRevert(VeridyMarketplace.NotSeller.selector);
        marketplace.acceptPurchase(purchaseId, ENC_K);
    }

    function test_AcceptPurchase_AutoRefundOtherPurchases() public {
        uint256 listingId = _createListing();

        uint256 purchaseId1 = _purchaseListing(listingId, buyer1);
        uint256 purchaseId2 = _purchaseListing(listingId, buyer2);
        uint256 purchaseId3 = _purchaseListing(listingId, buyer3);

        uint256 buyer2BalanceBefore = usdt.balanceOf(buyer2);
        uint256 buyer3BalanceBefore = usdt.balanceOf(buyer3);

        vm.expectEmit(true, true, true, true);
        emit PurchaseCancelled(purchaseId2, listingId, buyer2);
        vm.expectEmit(true, true, true, true);
        emit PurchaseCancelled(purchaseId3, listingId, buyer3);
        vm.expectEmit(true, true, true, true);
        emit PurchaseAccepted(purchaseId1, listingId, seller, ENC_K);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId1, ENC_K);

        VeridyMarketplace.Purchase memory purchase1 = marketplace.getPurchase(purchaseId1);
        assertEq(uint256(purchase1.status), uint256(VeridyMarketplace.PurchaseStatus.Accepted));

        VeridyMarketplace.Purchase memory purchase2 = marketplace.getPurchase(purchaseId2);
        assertEq(uint256(purchase2.status), uint256(VeridyMarketplace.PurchaseStatus.Cancelled));
        assertEq(usdt.balanceOf(buyer2), buyer2BalanceBefore + LISTING_PRICE);

        VeridyMarketplace.Purchase memory purchase3 = marketplace.getPurchase(purchaseId3);
        assertEq(uint256(purchase3.status), uint256(VeridyMarketplace.PurchaseStatus.Cancelled));
        assertEq(usdt.balanceOf(buyer3), buyer3BalanceBefore + LISTING_PRICE);

        assertEq(usdt.balanceOf(address(marketplace)), 0);
    }

    function test_CancelPurchase() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);
        uint256 buyer1BalanceBefore = usdt.balanceOf(buyer1);

        vm.expectEmit(true, true, true, true);
        emit PurchaseCancelled(purchaseId, listingId, buyer1);

        vm.prank(buyer1);
        marketplace.cancelPurchase(purchaseId);

        assertEq(usdt.balanceOf(buyer1), buyer1BalanceBefore + LISTING_PRICE);
        assertEq(usdt.balanceOf(address(marketplace)), 0);

        VeridyMarketplace.Purchase memory purchase = marketplace.getPurchase(purchaseId);
        assertEq(uint256(purchase.status), uint256(VeridyMarketplace.PurchaseStatus.Cancelled));

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertFalse(listing.sold);
    }

    function test_CancelPurchase_CanPurchaseAgain() public {
        uint256 listingId = _createListing();
        uint256 purchaseId1 = _purchaseListing(listingId, buyer1);

        vm.prank(buyer1);
        marketplace.cancelPurchase(purchaseId1);

        uint256 purchaseId2 = _purchaseListing(listingId, buyer1);
        assertEq(purchaseId2, 2);
    }

    function test_CancelPurchase_RevertPurchaseNotFound() public {
        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.PurchaseNotFound.selector);
        marketplace.cancelPurchase(999);
    }

    function test_CancelPurchase_RevertNotBuyer() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        vm.prank(buyer2);
        vm.expectRevert(VeridyMarketplace.NotBuyer.selector);
        marketplace.cancelPurchase(purchaseId);
    }

    function test_CancelPurchase_RevertInvalidPurchaseStatus_Accepted() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId, ENC_K);

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.InvalidPurchaseStatus.selector);
        marketplace.cancelPurchase(purchaseId);
    }

    function test_CancelPurchase_RevertInvalidPurchaseStatus_AlreadyCancelled() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        vm.prank(buyer1);
        marketplace.cancelPurchase(purchaseId);

        vm.prank(buyer1);
        vm.expectRevert(VeridyMarketplace.InvalidPurchaseStatus.selector);
        marketplace.cancelPurchase(purchaseId);
    }

    function test_GetListing() public {
        uint256 listingId = _createListing();

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.title, "Test Dataset");
    }

    function test_GetPurchase() public {
        uint256 listingId = _createListing();
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        VeridyMarketplace.Purchase memory purchase = marketplace.getPurchase(purchaseId);
        assertEq(purchase.buyer, buyer1);
        assertEq(purchase.listingId, listingId);
    }

    function test_GetListings_Pagination() public {
        for (uint256 i = 0; i < 5; i++) {
            _createListing();
        }

        (uint256[] memory ids1, VeridyMarketplace.DataListing[] memory listings1) = marketplace.getListings(1, 3);
        assertEq(ids1.length, 3);
        assertEq(ids1[0], 1);
        assertEq(ids1[1], 2);
        assertEq(ids1[2], 3);

        (uint256[] memory ids2, VeridyMarketplace.DataListing[] memory listings2) = marketplace.getListings(4, 3);
        assertEq(ids2.length, 2);
        assertEq(ids2[0], 4);
        assertEq(ids2[1], 5);

        (uint256[] memory ids3,) = marketplace.getListings(10, 3);
        assertEq(ids3.length, 0);

        (uint256[] memory ids4,) = marketplace.getListings(0, 3);
        assertEq(ids4.length, 3);
        assertEq(ids4[0], 1);
    }

    function test_GetActiveListings() public {
        for (uint256 i = 0; i < 5; i++) {
            _createListing();
        }

        vm.prank(seller);
        marketplace.deactivateListing(2);
        vm.prank(seller);
        marketplace.deactivateListing(4);

        (uint256[] memory ids, VeridyMarketplace.DataListing[] memory listings) = marketplace.getActiveListings(1, 10);
        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 3);
        assertEq(ids[2], 5);
    }

    function test_GetListingsBySeller() public {
        _createListing();
        _createListing();

        vm.prank(buyer1);
        marketplace.createListing(BUYER_PUBLIC_KEY, "hash", "QmCid", "Buyer1 Listing", "desc", "csv", 1000, 50 * 1e6);

        (uint256[] memory ids, VeridyMarketplace.DataListing[] memory listings) =
            marketplace.getListingsBySeller(seller);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);

        (uint256[] memory buyerIds,) = marketplace.getListingsBySeller(buyer1);
        assertEq(buyerIds.length, 1);
        assertEq(buyerIds[0], 3);
    }

    function test_GetPurchasesByBuyer() public {
        uint256 listingId1 = _createListing();
        uint256 listingId2 = _createListing();

        _purchaseListing(listingId1, buyer1);
        _purchaseListing(listingId2, buyer1);

        (uint256[] memory ids, VeridyMarketplace.Purchase[] memory purchaseData) =
            marketplace.getPurchasesByBuyer(buyer1);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }

    function test_GetPurchasesForListing() public {
        uint256 listingId = _createListing();

        _purchaseListing(listingId, buyer1);
        _purchaseListing(listingId, buyer2);
        _purchaseListing(listingId, buyer3);

        (uint256[] memory ids, VeridyMarketplace.Purchase[] memory purchaseData) =
            marketplace.getPurchasesForListing(listingId);
        assertEq(ids.length, 3);
    }

    function test_GetPendingPurchasesForSeller() public {
        uint256 listingId1 = _createListing();
        uint256 listingId2 = _createListing();

        uint256 purchaseId1 = _purchaseListing(listingId1, buyer1);
        uint256 purchaseId2 = _purchaseListing(listingId1, buyer2);
        uint256 purchaseId3 = _purchaseListing(listingId2, buyer1);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId1, ENC_K);

        (uint256[] memory ids, VeridyMarketplace.Purchase[] memory purchaseData) =
            marketplace.getPendingPurchasesForSeller(seller);

        assertEq(ids.length, 1);
        assertEq(ids[0], purchaseId3);
    }

    function test_GetCompletedPurchasesByBuyer() public {
        uint256 listingId1 = _createListing();
        uint256 listingId2 = _createListing();

        uint256 purchaseId1 = _purchaseListing(listingId1, buyer1);
        uint256 purchaseId2 = _purchaseListing(listingId2, buyer1);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId1, ENC_K);

        (uint256[] memory ids, VeridyMarketplace.Purchase[] memory purchaseData) =
            marketplace.getCompletedPurchasesByBuyer(buyer1);
        assertEq(ids.length, 1);
        assertEq(ids[0], purchaseId1);
        assertEq(purchaseData[0].encK, ENC_K);
    }

    function test_GetTotalListings() public {
        assertEq(marketplace.getTotalListings(), 0);

        _createListing();
        assertEq(marketplace.getTotalListings(), 1);

        _createListing();
        assertEq(marketplace.getTotalListings(), 2);
    }

    function test_GetTotalPurchases() public {
        uint256 listingId = _createListing();

        assertEq(marketplace.getTotalPurchases(), 0);

        _purchaseListing(listingId, buyer1);
        assertEq(marketplace.getTotalPurchases(), 1);

        _purchaseListing(listingId, buyer2);
        assertEq(marketplace.getTotalPurchases(), 2);
    }

    function test_HasBuyerPurchasedListing() public {
        uint256 listingId = _createListing();

        (bool hasPurchased1, uint256 pId1) = marketplace.hasBuyerPurchasedListing(listingId, buyer1);
        assertFalse(hasPurchased1);
        assertEq(pId1, 0);

        uint256 purchaseId = _purchaseListing(listingId, buyer1);
        (bool hasPurchased2, uint256 pId2) = marketplace.hasBuyerPurchasedListing(listingId, buyer1);
        assertFalse(hasPurchased2);
        assertEq(pId2, 0);

        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId, ENC_K);
        (bool hasPurchased3, uint256 pId3) = marketplace.hasBuyerPurchasedListing(listingId, buyer1);
        assertTrue(hasPurchased3);
        assertEq(pId3, purchaseId);
    }

    function test_OwnerIsDeployer() public view {
        assertEq(marketplace.owner(), owner);
    }

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        marketplace.transferOwnership(newOwner);

        assertEq(marketplace.owner(), newOwner);
    }

    function test_TransferOwnership_RevertNotOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(seller);
        vm.expectRevert();
        marketplace.transferOwnership(newOwner);
    }

    function test_FullPurchaseFlow() public {
        uint256 listingId = _createListing();

        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        assertEq(usdt.balanceOf(address(marketplace)), LISTING_PRICE);
        VeridyMarketplace.Purchase memory purchaseBefore = marketplace.getPurchase(purchaseId);
        assertEq(uint256(purchaseBefore.status), uint256(VeridyMarketplace.PurchaseStatus.Escrowed));
        assertEq(purchaseBefore.encK, bytes32(0));

        uint256 sellerBalanceBefore = usdt.balanceOf(seller);
        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId, ENC_K);

        assertEq(usdt.balanceOf(seller), sellerBalanceBefore + LISTING_PRICE);
        assertEq(usdt.balanceOf(address(marketplace)), 0);

        VeridyMarketplace.Purchase memory purchaseAfter = marketplace.getPurchase(purchaseId);
        assertEq(uint256(purchaseAfter.status), uint256(VeridyMarketplace.PurchaseStatus.Accepted));
        assertEq(purchaseAfter.encK, ENC_K);

        VeridyMarketplace.DataListing memory listing = marketplace.getListing(listingId);
        assertTrue(listing.sold);
    }

    function test_MultipleListingsAndPurchases() public {
        uint256 listingId1 = _createListing();
        uint256 listingId2 = _createListing();

        uint256 p1 = _purchaseListing(listingId1, buyer1);
        uint256 p2 = _purchaseListing(listingId1, buyer2);

        uint256 p3 = _purchaseListing(listingId2, buyer1);

        uint256 buyer1BalanceBefore = usdt.balanceOf(buyer1);
        vm.prank(seller);
        marketplace.acceptPurchase(p2, ENC_K);

        assertEq(usdt.balanceOf(buyer1), buyer1BalanceBefore + LISTING_PRICE);

        assertTrue(marketplace.getListing(listingId1).sold);
        assertFalse(marketplace.getListing(listingId2).sold);

        vm.prank(seller);
        marketplace.acceptPurchase(p3, ENC_K);

        assertTrue(marketplace.getListing(listingId2).sold);
    }

    function test_ActivePurchaseTrackingCleared() public {
        uint256 listingId = _createListing();

        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        assertEq(marketplace.activePurchase(listingId, buyer1), purchaseId);

        vm.prank(buyer1);
        marketplace.cancelPurchase(purchaseId);

        assertEq(marketplace.activePurchase(listingId, buyer1), 0);

        uint256 newPurchaseId = _purchaseListing(listingId, buyer1);
        assertEq(marketplace.activePurchase(listingId, buyer1), newPurchaseId);
    }

    function testFuzz_CreateListing_Price(uint256 price) public {
        vm.assume(price > 0);
        vm.assume(price < type(uint128).max);

        vm.prank(seller);
        uint256 listingId =
            marketplace.createListing(SELLER_PUBLIC_KEY, "hash", "QmCid", "title", "desc", "csv", 1000, price);

        assertEq(marketplace.getListing(listingId).price, price);
    }

    function testFuzz_PurchaseAndAccept_Amount(uint256 price) public {
        vm.assume(price > 0);
        vm.assume(price <= 1000 * 1e6);

        vm.prank(seller);
        uint256 listingId =
            marketplace.createListing(SELLER_PUBLIC_KEY, "hash", "QmCid", "title", "desc", "csv", 1000, price);

        uint256 buyer1BalanceBefore = usdt.balanceOf(buyer1);
        uint256 purchaseId = _purchaseListing(listingId, buyer1);

        assertEq(usdt.balanceOf(buyer1), buyer1BalanceBefore - price);

        uint256 sellerBalanceBefore = usdt.balanceOf(seller);
        vm.prank(seller);
        marketplace.acceptPurchase(purchaseId, ENC_K);

        assertEq(usdt.balanceOf(seller), sellerBalanceBefore + price);
    }
}
