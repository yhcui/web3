// SPDX-License-Identifier:MIT


pragma solidity ^0.8.0;

interface IshibMeme{

    // 税费

    function setTaxRates(uint256 _buyTax, uint256 _sellTax) external;
    // 税费分配
    function setTaxDistribution(
        uint256 _liquidityTax,
        uint256 _marketingTax,
        uint256 _devTax,
        uint256 _burnTax
    ) external;
    // 税费分配钱包地址
    function setTaxwallet(
        address _liquidityTaxwallet,
        address _marketingTaxwallet,
        address _devTaxwallet
    ) external;

    // 免税地址
    function setExcludedFromFees(
        address _address,
        bool _excluded
    ) external;

    // 设置交易限制
    function setLimits(uint256 _maxTxAmount, uint256 _maxWalletAmount) external;

    /**
     * @dev 启用交易
     */
    function enableTrading() external;
    
    // 免限制地址
    function setExcludedFromLimits( address _address,bool _excluded) external;
    // 是否启动限制
    function setLimitEnable(bool _enabled)external;
    // 设置冷却时间
    function setCooldownTime(uint256 _time)external;
    // 设置阈值
    function setSwapThreshold(uint256 threshold) external;
    // 黑名单
    function setBlackAddress(address _address,bool is_black)external;



    function getTaxRates()external view returns(uint256 buyTax, uint256 sellTax);
    function getLimits() external view returns (
        uint256 maxTxAmount,
        uint256 maxWalletAmount,
        uint256 cooldownPeriod
    );

    function isBlacklisted(address account) external view  returns (bool);
    function isExcludedFromFees(address account) external view  returns (bool);



    










}