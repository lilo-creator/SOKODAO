import { expect } from "chai";
import { ethers } from "hardhat";

describe("SOKODAO Marketplace", function () {
  let sokodao, escrow;
  let deployer, seller, buyer, platform;

  beforeEach(async function () {
    [deployer, seller, buyer, platform] = await ethers.getSigners();

    // Deploy SOKODAO (Product Listing contract)
    const SOKODAO = await ethers.getContractFactory("SOKODAO");
    sokodao = await SOKODAO.deploy();
    await sokodao.waitForDeployment();

    // Deploy MarketplaceEscrow contract
    const EscrowFactory = await ethers.getContractFactory("MarketplaceEscrow");
    escrow = await EscrowFactory.deploy(await sokodao.getAddress(), platform.address);
    await escrow.waitForDeployment();
  });

  it("Should allow seller to list a product", async function () {
    const tx = await sokodao.connect(seller).listProduct(
      "Web3 T-shirt",
      "Limited edition blockchain tee",
      "QmFakeIpfsHash",
      ethers.parseEther("0.05"),
      10
    );

    await tx.wait();

    const product = await sokodao.getProduct(1);
    expect(product.name).to.equal("Web3 T-shirt");
    expect(product.price).to.equal(ethers.parseEther("0.05"));
    expect(product.stock).to.equal(10);
  });

  it("Should allow buyer to purchase a product via escrow", async function () {
    // Seller lists product
    await sokodao.connect(seller).listProduct(
      "Web3 Hoodie",
      "Stylish hoodie for crypto lovers",
      "QmIpfsHashHoodie",
      ethers.parseEther("0.1"),
      5
    );

    // Buyer buys 2 units
    const tx = await escrow.connect(buyer).buyProduct(1, 2, {
      value: ethers.parseEther("0.2"),
    });
    await tx.wait();

    const order = await escrow.getOrder(1);
    expect(order.buyer).to.equal(buyer.address);
    expect(order.quantity).to.equal(2n);
    expect(order.totalPrice).to.equal(ethers.parseEther("0.2"));
  });

  it("Should allow seller to mark order as shipped", async function () {
    // Seller lists
    await sokodao.connect(seller).listProduct(
      "DAO Mug",
      "SokoDAO branded mug",
      "QmFakeHashMug",
      ethers.parseEther("0.03"),
      5
    );

    // Buyer buys
    await escrow.connect(buyer).buyProduct(1, 1, { value: ethers.parseEther("0.03") });

    // Seller marks as shipped
    const tx = await escrow.connect(seller).markAsShipped(1);
    await tx.wait();

    const order = await escrow.getOrder(1);
    expect(order.status).to.equal(1); // Enum: 0=Pending, 1=Shipped
  });

  it("Should release funds after buyer confirms delivery", async function () {
    // Seller lists
    await sokodao.connect(seller).listProduct(
      "NFT Poster",
      "High-quality digital art",
      "QmFakePoster",
      ethers.parseEther("1"),
      2
    );

    // Buyer buys
    await escrow.connect(buyer).buyProduct(1, 1, { value: ethers.parseEther("1") });

    // Seller marks as shipped
    await escrow.connect(seller).markAsShipped(1);

    // Record seller balance before confirmation
    const balanceBefore = await ethers.provider.getBalance(seller.address);

    // Buyer confirms delivery
    const tx = await escrow.connect(buyer).confirmDelivery(1);
    await tx.wait();

    const balanceAfter = await ethers.provider.getBalance(seller.address);
    expect(balanceAfter).to.be.gt(balanceBefore); // Seller received funds
  });
});
