pragma solidity ^0.5.0;

import "./ERC20.sol";
import "./ValidatorRegistry.sol";
import "./CarbonCreditToken.sol";
import "./Company.sol";

contract CarbonCreditMarket {
    event BuyCredit(address buyer, uint256 amount);
    event ReturnCredits(address seller, uint256 amount);
    event ProjectValidated(
        address companyAddress,
        uint256 projectId,
        bool isValid
    );
    event Penalty(address companyAddress, uint256 projectId);

    CarbonCreditToken carbonCreditTokenInstance;
    ValidatorRegistry validatorRegistryInstance;
    Company companyInstance;
    address _owner = msg.sender;
    mapping(address => bool) public isVerifier;
    mapping(address => bool) public isSeller;
    mapping(address => uint256[]) public companyProjects; // Mapping of company address to list of projects
    mapping(uint256 => address[]) public projectBuyers; // Mapping of project id to list of buyers
    mapping(address => mapping(uint256 => uint256)) public projectStakes; //mapping of buyer address to project id to amount

    constructor(
        Company companyAddress,
        CarbonCreditToken carbonCreditTokenAddress,
        ValidatorRegistry validatorRegistryAddress
    ) public {
        carbonCreditTokenInstance = carbonCreditTokenAddress;
        validatorRegistryInstance = validatorRegistryAddress;
        companyInstance = companyAddress;
    }

    modifier onlyOwner() {
        require(
            msg.sender == _owner,
            "Only contract owner can call this function"
        );
        _;
    }

    modifier onlyValidator() {
        require(
            validatorRegistryInstance.isValidator(msg.sender),
            "Only validator can call this function"
        );
        _;
    }

    function withdrawEther(
        address payable companyAddress,
        uint256 amount
    ) public onlyOwner {
        require(
            amount <= address(this).balance,
            "Insufficient contract balance"
        );
        companyAddress.transfer(amount);
    }

    // Validate a project by a validator, and handle penalty if project is invalid, otherwise transfer CCT to buyers
    function validateProject(
        address companyAddress,
        uint256 projectId,
        bool isValid,
        uint256 actualCCT
    ) public onlyValidator {
        companyInstance.projects[projectId].state = Company
            .ProjectState
            .completed; // Set project state to completed
        emit ProjectValidated(companyAddress, projectId, isValid); // Emit event for project validation
        if (!isValid) {
            handlePenalty(companyAddress, projectId, actualCCT);
        } else {
            // Project is valid
            //Transfer CCT to buyers
            uint256[] storage buyers = projectBuyers[projectId];
            for (uint256 i = 0; i < buyers.length; i++) {
                address buyer = buyers[i];
                uint256 buyerStake = projectStakes[buyer][projectId]; // Get buyer's stake for the project
                carbonCreditTokenInstance.getCCT(buyer, buyerStake); // Mint CCT to buyer
                projectStakes[buyer][projectId] = 0; // Reset buyer's stake to 0
            }
            //Project's CCTAmount left is returned to company project
            uint256 cctAmountUnsold = companyInstance
                .projects[projectId]
                .cctAmount;
            carbonCreditTokenInstance.getCCT(companyAddress, cctAmountUnsold); // Mint CCT to company to return unsold CCT;
            // Return penalty + profit to seller
            uint256 stakedCredits = companyInstance.getStakedCredits(
                companyAddress,
                projectId
            );
            uint256 returnPenalty = (stakedCredits * penaltyRate) / 100; // Calculate penalty amount to return to seller
            withdrawEther(companyAddress, returnPenalty + companyInstance
                .projects[projectId]
                .cctSoldAmount;); // Return penalty amount and profit back to seller
                 companyInstance.projects[projectId].cctAmount = 0; // Set project's CCT amount to 0, project can't be resold
        }
    }

    // Handle penalty for a project that fails validation
    function handlePenalty(
        address companyAddress,
        uint256 projectId,
        uint256 actualCCT // Actual CCT generated by the project
    ) internal {
        emit Penalty(companyAddress, projectId);
        for (uint256 i = 0; i < projectBuyers[projectId].length; i++) { // Loop through buyers of the project
            address buyer = projectBuyers[projectId][i]; // Get buyer address
            uint256 buyerStake = projectStakes[buyer][projectId]; // Get buyer's stake for the project
            if (actualCCT >= companyInstance.projects[projectId].cctSold) { // If actual CCT is greater than or equal to CCT sold
                carbonCreditTokenInstance.getCCT(buyer, buyerStake); // Mint actual CCT to buyer, penalty and profits kept by market
                actualCCT -= buyerStake; // Reduce actual CCT by buyer's stake
                companyInstance.projects[projectId].cctAmount = actualCCT; // Update project's CCT amount, project can be resold with remaining CCT by seller 
            } else { // If actual CCT is less than CCT sold
                uint256 actualBuyerCCT = (buyerStake * actualCCT) / companyInstance.projects[projectId].cctSold; // Calculate actual CCT received by the buyer
                carbonCreditTokenInstance.getCCT(buyer, actualBuyerCCT); // Mint actual CCT to buyer
                uint256 buyerCompensation = buyerStake - actualBuyerCCT; // Calculate compensation amount to buyer
                withdrawEther(buyer, buyerCompensation ); // Transfer compensation amount to buyer
            }
            withdrawEther(companyAddress, companyInstance.projects[projectId].cctSoldAmount); // Transfer profits to company, penalty kept by market
            projectStakes[buyer][projectId] = 0; // Reset buyer's stake to 0
        }
    }

    function sell(uint256 _cctAmount, uint256 projectId) public {
        //seller lists cct for sale anytime during project
        require(_cctAmount > 0, "Invalid amount");
        require(
            companyInstance.projects[projectId].cctListed <=
                companyInstance.projects[projectId].cctAmount,
            "Invalid Selling Price"
        ); // Check if cctListed is <= to cctAmount, must have enuf cctAmount in project to sell 
        require(
            companyInstance.checkCCTListed(msg.sender, projectId, _cctAmount),
            "CCT for project overexceeded"
        );
        require(
            companyInstance.checkSufficientCCT(
                msg.sender,
                projectId,
                _cctAmount
            ),
            "Insufficient CCT to sell"
        );
        //check if company has enough ether to stake
        require(
            companyInstance.checkSufficientEther(
                msg.sender,
                projectId,
                _cctAmount
            ),
            "Insufficient ether to stake"
        );
        //Transfer the ether to contract for staking
        uint256 stakedAmount = (_cctAmount * 13) / 10; // sellers stake 130% (of ether), 30% is penalty
        companyInstance.stakeCredits(msg.sender, projectId, stakedAmount); //stake credits
        msg.sender.transfer(stakedAmount); // Seller Transfer 130% ether to contract for staking, 30% is penalty
        companyInstance.listCCT(msg.sender, projectId, _cctAmount); //update cctListed and cctAmount in project

        //Check if project has been added by company
        uint256[] storage projectList = companyProjects[msg.sender];
        bool projectAdded = false;
        for (uint256 i = 0; i < projectList.length; i++) {
            if (projectList[i] == projectId) {
                projectAdded = true; // project already added
            }
        }
        if (!projectAdded) {
            companyProjects[msg.sender].push(projectId); // add project to list of projects
        }
        isSeller[msg.sender] = true; // add address of seller to list of sellers
        emit ReturnCredits(msg.sender, _cctAmount);
    }

    function buy(
        uint256 _cctAmount,
        address companyAddress,
        uint256 projectId
    ) public payable {
        require(_cctAmount > 0, "Invalid amount");
        require(msg.value == _cctAmount, "Invalid amount"); //ensure buyer gave correct amount of ether to contract for buying
        require(
            companyInstance.checkSufficientCCT(
                msg.sender,
                projectId,
                _cctAmount
            ),
            "Insufficient CCT in project to buy"
        );
        //carbonCreditTokenInstance.transferCCT(msg.sender, _cctAmount);
        companyInstance.sellCCT(companyAddress, projectId, _cctAmount); //sell, update cctSold in project
        projectStakes[msg.sender][projectId] += _cctAmount; // add "share" of the project's CCT bought to the buyer
        address[] storage buyerList = projectBuyers[projectId];
        bool buyerAdded = false;
        for (uint256 i = 0; i < buyerList.length; i++) {
            if (buyerList[i] == msg.sender) {
                buyerAdded = true;
            }
        }
        if (!buyerAdded) {
            projectBuyers[projectId].push(msg.sender);
        }
        emit BuyCredit(msg.sender, _cctAmount);
    }
}
