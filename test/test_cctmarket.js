const _deploy_contracts = require("../migrations/5_deploy_contracts");

var CarbonCreditMarket = artifacts.require("CarbonCreditMarket");
var Company = artifacts.require("Company");
var ValidatorRegistry = artifacts.require("ValidatorRegistry");

const oneEth = 1000000000000000000; // 1 eth

contract("CarbonCreditMarket", function (accounts) {
  let companyInstance = null;
  const owner = accounts[0];
  const companyAddress = accounts[1];

  before(async () => {
    validatorRegistryInstance = await ValidatorRegistry.deployed();
    companyInstance = await Company.deployed();
    carbonCreditMarketInstance = await CarbonCreditMarket.deployed();
  });
  console.log("Testing CarbonCreditMarket contract");

  it("Should add a company", async () => {
    await companyInstance.addCompany(companyAddress, "Test Company", {
      from: owner,
    });
    const companyInstanceData = await companyInstance.getCompanyName(
      companyAddress
    );
    assert(companyInstanceData === "Test Company");
  });

  it("Should not add a company if not owner", async () => {
    try {
      await companyInstance.addCompany(companyAddress, "Test Company", {
        from: companyAddress,
      });
    } catch (e) {
      assert(
        e.message.includes("Only contract owner can execute this function")
      );
      return;
    }
    assert(false);
  });

  it("Should add a project", async () => {
    await companyInstance.addProject(
      "Test Project",
      "Test Description",
      1000,
      3
    );
    const projectData = await companyInstance.projects(0);
    assert(projectData.projectName === "Test Project");
    assert(projectData.cctAmount.toNumber() === 3);
  });

  it("Selling CCT from Project", async () => {
    let sellCCT = await carbonCreditMarketInstance.sell(3, 0, {
      from: companyAddress,
      value: oneEth * 6,
    });
    assert.eventEmitted(sellCCT, "EtherReceived", null, "Ether not received");
    const projectData = await companyInstance.projects(0);
    assert(projectData.cctListed.toNumber() === 3, "CCT not listed");
    const projectList = await carbonCreditMarketInstance.companyProjects(0);
    const project = projectList[0];
    assert(project.projectName === "Test Project");
  });
});
