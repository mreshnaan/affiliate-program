//SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Affiliate is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;

    //File type
    string public uriSuffix = ".json";

    //Prices
    uint256 public cost = 0 ether;

    //Inventory
    bytes32 private affiliateRoot;
    string public baseURI;

    //supplies
    uint256 public mintSupply = 7500;

    //limits
    uint256 public maxMintAmountPerWallet = 50;

    //Utility
    bool public paused = false;

    //keep track of wallet
    mapping(address => uint256) public addressMintedBalance;
    mapping(bytes8 => bool) public secretChecker;

    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _mintSupply,
        uint256 _maxMintAmountPerWallet,
        string memory _initialURI
    ) ERC721A(_tokenName, _tokenSymbol) {
        //set  mintSupply supply amount
        setMintSupply(_mintSupply);
        //set max mint amount per wallet
        setMaxMintAmountPerWallet(_maxMintAmountPerWallet);
        //set initial URI
        baseURI = _initialURI;
    }

    //keep track of affiliate program secret keys
    event referral(
        address indexed minter,
        address indexed _referred,
        bytes8 _secret
    );

    /**
     * Do not allow calls from other contracts.
     */
    modifier noBots() {
        require(msg.sender == tx.origin, "No bots");
        _;
    }

    /**
     * Ensure amount of per wallet is within the mint limit.
     * Ensure amount of tokens to mint is within the limit.
     */
    modifier mintLimitCompliance(uint256 _mintAmount) {
        require(_mintAmount > 0, "Mint amount should be greater than 0");
        require(
            addressMintedBalance[msg.sender] + _mintAmount <=
                maxMintAmountPerWallet,
            "Sale allowance Exceeds"
        );
        require(
            totalSupply() + _mintAmount <= mintSupply,
            "Max supply Exceeded"
        );
        _;
    }

    /**
     * Set the presale Merkle root.
     * @dev The Merkle root is calculated from [secret] pairs.
     * @param _root The new merkle root
     */
    function setWhitelistingRoot(bytes32 _root) public onlyOwner {
        affiliateRoot = _root;
    }

    /**
     * Verify the Merkle proof is valid.
     * @param _leafNode The leaf. A [secret, availableAmt] pair
     * @param proof The Merkle proof used to validate the leaf is in the root
     */
    function _verify(bytes32 _leafNode, bytes32[] memory proof)
        internal
        view
        returns (bool)
    {
        return MerkleProof.verify(proof, affiliateRoot, _leafNode);
    }

    /**
     * Generate the leaf node
     * @param secret used the hash of tokenID concatenated with the affiliate secret
     */
    function _leaf(bytes8 secret) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(secret));
    }

    /**
     * Affiliate marketing
     * @notice This function is only available to those whom referred.
     * @param _mintAmount The number of tokens to mint.
     * @param secret referral secret number.
     * @param proof The Merkle proof used to validate the leaf in the root.
     */
    function affiliateMint(
        bytes32[] calldata proof,
        bytes8 secret,
        uint256 _mintAmount,
        address referred
    ) external payable noBots mintLimitCompliance(_mintAmount) {
        require(!paused, "The contract is paused!");
        require(!secretChecker[secret], " Already referred ");
        require(referred != msg.sender, " You cannot refer yourself ");
        require(_verify(_leaf(secret), proof), "Invalid proof");
        require(msg.value == cost);
        uint256 mintTax = (msg.value * 15) / 100;

        (bool success, ) = payable(referred).call{value: mintTax}("");
        require(success);

        _mintLoop(msg.sender, _mintAmount);
        secretChecker[secret] = true;
        addressMintedBalance[msg.sender] += _mintAmount;

        emit referral(msg.sender, referred, secret);
    }

    /**
     * Normal mint.
     * @param _mintAmount Amount of tokens to mint.
     */
    function mint(uint256 _mintAmount)
        external
        payable
        noBots
        mintLimitCompliance(_mintAmount)
    {
        require(!paused, "The contract is paused!");
        _mintLoop(msg.sender, _mintAmount);
        addressMintedBalance[msg.sender] += _mintAmount;
    }

    /**
     * airdrop mint.
     * @param _mintAmount Amount of tokens to mint.
     * @param _receiver Address to mint to.
     */
    function mintForAddress(uint256 _mintAmount, address _receiver)
        external
        noBots
        onlyOwner
    {
        require(_mintAmount > 0, "Mint amount should be greater than 0");
        _mintLoop(_receiver, _mintAmount);
    }

    /**
     * @dev Returns the starting token ID.
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /**
     * Change the baseURI.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        uriSuffix
                    )
                )
                : "";
    }

    /**
     * Update token price.
     * @param _cost The new token price.
     */
    function setCost(uint256 _cost) public onlyOwner {
        cost = _cost;
    }

    /**
     * Update colletion MintSupply.
     * @param _supply token supply.
     */
    function setMintSupply(uint256 _supply) public onlyOwner {
        mintSupply = _supply;
    }

    /**
     * Update sales mint limit per wallet.
     * @param _maxMintAmountPerWallet token limit.
     */
    function setMaxMintAmountPerWallet(uint256 _maxMintAmountPerWallet)
        public
        onlyOwner
    {
        maxMintAmountPerWallet = _maxMintAmountPerWallet;
    }

    /**
     * Sets base URI.
     * @param _newBaseURI The base URI.
     */
    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    /**
     * Sets file type at the end of url.
     * @param _uriSuffix The base URI.
     */
    function setUriSuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    /**
     * On and Off public sales.
     */
    function togglePause() public onlyOwner {
        paused = !paused;
    }

    function _mintLoop(address _receiver, uint256 _mintAmount) internal {
        _safeMint(_receiver, _mintAmount);
    }

    function withdraw() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "Not have Eth");
        // =============================================================================
        // remaining funds ill be transfer to owner
        // =============================================================================
        (bool os, ) = payable(owner()).call{value: balance}("");
        require(os, "Failed to send to owner wallet.");
        // =============================================================================
    }
}
