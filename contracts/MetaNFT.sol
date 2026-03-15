// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MetaNFT is ERC721 {
    address private _owner;

    constructor() ERC721("MetaNFT", "MFT") {
        _mint(msg.sender, 1);
        _owner = msg.sender;
    }

    modifier onlyOwner {
        require(_owner == msg.sender, "not owner");
        _;
    }

    function mint(address to, uint256 id) external onlyOwner {
        _safeMint(to, id);
    }

    function burn(uint256 id) external onlyOwner {
        require(msg.sender == ownerOf(id), "not owner");
        _burn(id);
    }
}