// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80, int256, uint256, uint256, uint80
    );
    function decimals() external view returns (uint8);
}

contract KipuBank_V3 is AccessControl {
    
    using SafeERC20 for IERC20;
    uint8 internal constant internalDecimals = 6;
    uint256 public immutable i_bankCapUSD;
    uint256 public immutable i_maxWithdrawInternal;
    AggregatorV3Interface public immutable i_priceFeedETHUSD;
    IUniswapV2Factory public immutable FACTORY;
    IERC20 public immutable USDC;

    mapping(address => uint256) public balances; // balance total en USDC
    mapping(address => uint256) public userDeposits;      // depósitos por usuario
    mapping(address => uint256) public userWithdrawals;   // retiros por usuario

    error KipuBank_FailedETHTransfer(bytes error);
    error KipuBank_ExceededMaxWithdraw(uint256 amount);
    error KipuBank_InsufficientBalance(uint256 balance);
    error KipuBank_ExceededBankCap();
    error SwapModule_InsufficientOutputAmount();
    error SwapModule_InsufficientLiquidity();

    event DepositSuccessful(address user, uint256 amount);
    event WithdrawSuccessful(address user, uint256 amount);

    constructor(
        uint256 bankCapUSD,
        uint256 maxWithdrawInternal,
        address priceFeedETHUSD,
        address factory_, 
        address usdc_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        i_bankCapUSD = bankCapUSD;
        i_maxWithdrawInternal = maxWithdrawInternal;
        i_priceFeedETHUSD = AggregatorV3Interface(priceFeedETHUSD);
        FACTORY = IUniswapV2Factory(factory_);
        USDC = IERC20(usdc_);
    }

    // Oráculo ETH -> USD
    function convertETHtoUSDInternal(uint256 ethAmount) public view returns (uint256) {
        (, int256 price,,,) = i_priceFeedETHUSD.latestRoundData();
        uint8 feedDecimals = i_priceFeedETHUSD.decimals();
        return (uint256(price) * ethAmount) / (10 ** feedDecimals);
    }

    function totalBankUSD() public view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    receive() external payable {
        _depositETH();
    }

    fallback() external payable {
        if(msg.value > 0) _depositETH();
    }

    function _depositETH() private {
        uint256 amountInternalUSD = convertETHtoUSDInternal(msg.value);
        if(amountInternalUSD + totalBankUSD() > i_bankCapUSD) revert KipuBank_ExceededBankCap();
        balances[msg.sender] += amountInternalUSD;

        userDeposits[msg.sender] += 1;

        emit DepositSuccessful(msg.sender, amountInternalUSD);
    }

    // Deposito de cualquier ERC20 -> se swappea a USDC
    function depositToken(
        address token,
        uint256 amount,
        uint256 amountOutMin
    ) external {
        require(amount > 0, "Amount must be > 0");

        // Transferir tokens desde el usuario al contrato
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Realizar swap a USDC verificando slippage
        uint256 usdcReceived = _swapTokenToUSDC(token, amount, amountOutMin);

        // Verificar que no exceda el bankCap
        if(usdcReceived + totalBankUSD() > i_bankCapUSD) revert KipuBank_ExceededBankCap();

        // Actualizar balance del usuario
        balances[msg.sender] += usdcReceived;

        // Contador de depósitos por usuario
        userDeposits[msg.sender] += 1;

        emit DepositSuccessful(msg.sender, usdcReceived);
    }

    function _swapTokenToUSDC(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        // Obtener par
        address pair = FACTORY.getPair(tokenIn, address(USDC));
        require(pair != address(0), "Pair does not exist");

        // Obtener reservas
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        bool token0IsTokenIn = token0 == tokenIn;

        // Calcular output esperado usando fórmula oficial de Uniswap V2
        uint256 amountOutExpected = getAmountOut(
            amountIn,
            token0IsTokenIn ? reserve0 : reserve1,
            token0IsTokenIn ? reserve1 : reserve0
        );

        // Verificar slippage mínimo
        if(amountOutExpected < amountOutMin) {
            revert SwapModule_InsufficientOutputAmount();
        }

        // Transferir tokens al par
        IERC20(tokenIn).safeTransfer(pair, amountIn);

        // Preparar parámetros del swap
        uint256 amount0Out = token0IsTokenIn ? 0 : amountOutExpected;
        uint256 amount1Out = token0IsTokenIn ? amountOutExpected : 0;

        // Registrar balance antes
        uint256 usdcBefore = USDC.balanceOf(address(this));

        // Ejecutar swap
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), "");

        // Calcular USDC recibido
        uint256 usdcReceived = USDC.balanceOf(address(this)) - usdcBefore;

        return usdcReceived;
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            revert SwapModule_InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * 997; // fee 0.3%
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    // Retiro siempre en USDC
    function withdraw(uint256 amount) external {
        uint256 balance = balances[msg.sender];
        if(balance < amount) revert KipuBank_InsufficientBalance(balance);
        if(amount > i_maxWithdrawInternal) revert KipuBank_ExceededMaxWithdraw(amount);

        balances[msg.sender] -= amount;
        USDC.safeTransfer(msg.sender, amount);

        userWithdrawals[msg.sender] += 1;

        emit WithdrawSuccessful(msg.sender, amount);
    }
}
