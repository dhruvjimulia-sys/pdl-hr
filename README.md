# Human Resources Smart Contract Documentation

## Implementation Details

### Data Structures
- `employeeActive`: Mapping tracking if an employee is currently active
- `isEmployee`: Mapping tracking if an address has ever been an employee
- `weeklySalary`: Mapping storing employee salaries in USD (18 decimals)
- `employedSince`: Mapping storing employee registration timestamps
- `terminatedAt`: Mapping storing termination timestamps
- `lastWithdrawn`: Mapping tracking last salary withdrawal timestamps
- `isEth`: Mapping tracking preferred payment currency (ETH/USDC)
- `accuredSalaryTillTermination`: Mapping storing final salary calculations for terminated employees
- `activeEmployeeCount`: Counter for current active employees

### Interface Implementation

#### HR Manager Functions
- `registerEmployee`: Updates all employee-related mappings and increments `activeEmployeeCount`
- `terminateEmployee`: Calculates final salary, updates `terminatedAt`, and decrements `activeEmployeeCount`

#### Employee Functions
- `withdrawSalary`: 
  - Uses `computeAccumulatedSalary` for amount calculation
  - Integrates with Uniswap for USDC->WETH swaps when needed
  - Updates `lastWithdrawn` and `accuredSalaryTillTermination`
- `switchCurrency`: Toggles `isEth` mapping after forcing salary withdrawal

#### View Functions
- `salaryAvailable`: Combines `computeAccumulatedSalary` with currency conversion
- `hrManager`: Returns immutable manager address
- `getActiveEmployeeCount`: Returns counter value
- `getEmployeeInfo`: Returns tuple of mapped values for employee

### Access Control

Access control is implemented using three modifiers:

- `onlyHRManager`: Restricts functions to the address stored in `hrManagerAddress`
  - Set during contract deployment to `msg.sender`
  - Used for administrative functions like employee registration and termination

- `onlyActiveEmployee`: Requires `employeeActive[msg.sender]`
  - Used for functions that should only be called by current employees
  - Applied to `switchCurrency`

- `onlyEmployee`: Requires `isEmployee[msg.sender]`
  - Allows both active and terminated employees
  - Applied to `withdrawSalary`

### External Integrations

#### Chainlink Oracle Integration
- Uses ETH/USD price feed (`0x13e3Ee699D1909E989722E753853AE30b17e08c5`) for accurate ETH payment calculations
- Integration via `CurrencyConvertUtils` library
- Oracle consulted in two scenarios:
  1. During salary withdrawals to calculate ETH equivalent for slippage protection
  2. In `salaryAvailable` view function for ETH balance display
- Oracle Implementation Details:
  - Uses `AggregatorV3Interface.latestRoundData()` to fetch most recent ETH/USD price
  - Price returned with 8 decimals precision. We need to multiply by 1e10 to get to 18 decimals in wei  (standard ETH precision)

#### Uniswap Integration
- Uses SwapRouter (`0xE592427A0AEce92De3Edee1F18E0157C05861564`) for USDC->WETH conversions
- Swap Parameters:
  - `fee`: 500 (0.05%) - Chosen for optimal balance between cost and liquidity in USDC/WETH pair
  - `deadline`: 30 seconds - Short window to prevent pending transaction exploitation
  - `amountOutMinimum`: Calculated using 2% slippage tolerance
    - Formula: `minimumAmount = expectedAmount * (100 - slippage) / 100`
    - Conservative slippage value chosen to protect against most market movements
  - `sqrtPriceLimitX96`: 0 (disabled) - No price limit to ensure swap execution
  - `recipient`: Contract address - WETH received before unwrapping to ETH

- Swap Process Flow:
  1. Approve USDC spending by router (`safeApprove`)
  2. Execute `exactInputSingle` with computed parameters
  3. Unwrap received WETH to ETH using WETH contract
  4. Transfer ETH to employee using low-level `call`

- Safety Mechanisms:
  - Oracle price used as reference for slippage calculation
  - Slippage protection prevents excessive value loss
  - Short deadline prevents sandwich attacks
  - Direct USDC→WETH path minimizes slippage vs multi-hop routes
