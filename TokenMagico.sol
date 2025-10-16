// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract TokenMagico is ERC20, Ownable, Pausable {
    // State variables
    address public treasury;
    uint256 public taxFee;
    
    // Mapping per gli indirizzi esenti dalla fee
    mapping(address => bool) private _isFeeExempt;
    
    // Eventi
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TaxFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeExemptionUpdated(address indexed account, bool isExempt);
    event FeeCollected(address indexed from, address indexed to, uint256 feeAmount);
    
    /**
     * @dev Constructor del contratto
     * @param _name Nome del token
     * @param _symbol Simbolo del token
     * @param _treasury Indirizzo della tesoreria
     * @param _taxFee Percentuale di imposta (0-100)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _treasury,
        uint256 _taxFee
    ) ERC20(_name, _symbol) {
        require(_treasury != address(0), "Treasury address cannot be zero");
        require(_taxFee <= 100, "Tax fee cannot exceed 100");
        
        treasury = _treasury;
        taxFee = _taxFee;
        
        // Il proprietario e la tesoreria sono esenti dalla fee di default
        _isFeeExempt[msg.sender] = true;
        _isFeeExempt[_treasury] = true;
        _isFeeExempt[address(0)] = true; // Mint/burn esenti
        
        // Mint iniziale di 1,000,000 token con 18 decimali
        _mint(msg.sender, 1_000_000 * 10**decimals());
    }
    
    /**
     * @dev Modifica l'indirizzo della tesoreria
     * @param _newTreasury Nuovo indirizzo della tesoreria
     */
    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Treasury address cannot be zero");
        address oldTreasury = treasury;
        treasury = _newTreasury;
        
        // Il nuovo indirizzo della tesoreria diventa esente
        _isFeeExempt[_newTreasury] = true;
        
        emit TreasuryUpdated(oldTreasury, _newTreasury);
    }
    
    /**
     * @dev Modifica la percentuale di imposta
     * @param _newTaxFee Nuova percentuale di imposta (0-100)
     */
    function setTaxFee(uint256 _newTaxFee) external onlyOwner {
        require(_newTaxFee <= 100, "Tax fee cannot exceed 100");
        uint256 oldFee = taxFee;
        taxFee = _newTaxFee;
        
        emit TaxFeeUpdated(oldFee, _newTaxFee);
    }
    
    /**
     * @dev Pausa tutte le trasferenze
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Riattiva tutte le trasferenze
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Imposta l'esenzione dalla fee per un indirizzo
     * @param _account Indirizzo da escludere o includere
     * @param _exempt True per escludere, false per includere
     */
    function setFeeExempt(address _account, bool _exempt) external onlyOwner {
        require(_account != address(0), "Cannot set fee exemption for zero address");
        _isFeeExempt[_account] = _exempt;
        
        emit FeeExemptionUpdated(_account, _exempt);
    }
    
    /**
     * @dev Verifica se un indirizzo è esente dalla fee
     * @param _account Indirizzo da verificare
     * @return True se l'indirizzo è esente
     */
    function isFeeExempt(address _account) external view returns (bool) {
        return _isFeeExempt[_account];
    }
    
    /**
     * @dev Override della funzione _beforeTokenTransfer per il pause
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        require(!paused(), "ERC20Pausable: token transfer while paused");
    }
    
    /**
     * @dev Override della funzione transfer per implementare la logica della fee
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transferWithFee(_msgSender(), recipient, amount);
        return true;
    }
    
    /**
     * @dev Override della funzione transferFrom per implementare la logica della fee
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transferWithFee(sender, recipient, amount);
        
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        
        return true;
    }
    
    /**
     * @dev Funzione interna per gestire i trasferimenti con fee
     */
    function _transferWithFee(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        
        _beforeTokenTransfer(sender, recipient, amount);
        
        // Verifica se il mittente o il destinatario sono esenti
        bool isExempt = _isFeeExempt[sender] || _isFeeExempt[recipient];
        
        // Se non ci sono fee da applicare o l'indirizzo è esente
        if (taxFee == 0 || isExempt) {
            _transfer(sender, recipient, amount);
            return;
        }
        
        // Calcola la fee
        uint256 feeAmount = (amount * taxFee) / 100;
        
        if (feeAmount > 0) {
            // Invia la fee alla tesoreria
            _transfer(sender, treasury, feeAmount);
            emit FeeCollected(sender, treasury, feeAmount);
            
            // Invia il resto al destinatario
            uint256 netAmount = amount - feeAmount;
            _transfer(sender, recipient, netAmount);
        } else {
            // Se la fee è 0, procedi normalmente
            _transfer(sender, recipient, amount);
        }
    }
}