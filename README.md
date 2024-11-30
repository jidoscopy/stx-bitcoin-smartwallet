**### README: Bitcoin Smart Wallet

#### Overview

The **Bitcoin Smart Wallet** contract provides secure and flexible financial management features using Stacks smart contracts. It enables users to create time-locked savings accounts, execute split payments, and initiate emergency withdrawals with predefined conditions. The contract ensures robust fund management through customizable lock periods and emergency settings.

#### Features

1. **Time-Locked Savings**:  
   - Users can lock funds for a specified period.
   - Supports emergency withdrawal with a fee.
   - Optional designation of an emergency contact.

2. **Split Payments**:  
   - Allows setting multiple recipients with customizable percentages.
   - Automates payments across recipients based on predefined shares.

3. **Emergency Withdrawal**:  
   - Permits early withdrawal under specific conditions.
   - Charges a configurable withdrawal fee.

4. **Administrative Controls**:  
   - Contract owner can adjust lock periods, fees, and block height to align with changing requirements.

#### Key Functions

- **Time-Locked Savings Functions**:
  - `create-time-lock(amount, lock-blocks, emergency-contact)`: Creates a locked savings account.
  - `withdraw()`: Withdraws funds after the lock period.
  - `emergency-withdraw()`: Withdraws funds prematurely with a fee.

- **Split Payment Functions**:
  - `set-split-payment(recipients, percentages)`: Configures recipients and their respective payment shares.
  - `execute-split-payment(amount)`: Executes a split payment based on predefined settings.

- **Admin Functions**:
  - `set-minimum-lock-period(new-period)`: Updates the minimum lock period.
  - `set-emergency-withdrawal-fee(new-fee)`: Modifies the emergency withdrawal fee.
  - `update-block-height(new-height)`: Updates the current block height.

#### Usage Notes
- **Time Lock Period**: The default lock period is approximately 10 days.
- **Emergency Fee**: Default withdrawal fee is 5% of the locked amount.
- **Split Payments**: Recipient list and their payment percentages must total 100%.

---**