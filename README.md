# KipuBankV3




# Mejoras Implementadas:
1) Normalizacion de contabilidad interna a USDC implementada a partir de UniswapV2
2) Proteccion frente a slippage al depositar tokens ERC-20
3) Soporte de depositos de ETH y tokens ERC-20
# Instrucciones de despliegue:
1) Abrir Remix IDE
2) Seleccionar compilador: 0.8.26
3) Importar tu contrato KipuBankV3.sol
4) Seleccionar Deploy & Run Transactions
5) Elegir environment (Injected Web3 para Metamask en mi caso)
6) Constructor del contrato requiere 3 parámetros:
bankCapUSD Límite máximo del banco en USD internos
maxWithdrawInternal Límite máximo de retiro por operación en internal decimals
priceFeedETHUSD el address de donde sacara el oraculo la informacion de precio de ETH
factory_ el address del contrato FACTORY de UNISWAPV2 deployado en la red a usar
USDC el address de USDC en la red a usar
# Tradeoffs
Implemente control de acceso con libreria OpenZeppelin, supone mayor facilidad para implementar el contrato pero mayor acople a dicha libreria
Contabilidad interna paso a ser token a token a tomar en cuenta todo en USDC. Mayor facilidad de calculos, pero pierde flexibilidad el banco a
la hora de retirar las mismas tokens que se ingresaron.

