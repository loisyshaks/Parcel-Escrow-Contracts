# 📦 Parcel Escrow Contracts

A secure Clarity smart contract system for parcel delivery with QR code/OTP verification on the Stacks blockchain.

## 🚀 Features

- 🔒 **Secure Escrow**: Funds locked until delivery confirmation
- 🔑 **QR/OTP Verification**: Unique verification codes for delivery confirmation  
- ⏰ **Time-based Refunds**: Automatic refund eligibility after expiration
- 💰 **Platform Fees**: Configurable fee structure
- 🛡️ **Emergency Controls**: Admin override capabilities
- 📱 **Multi-user Support**: Track multiple escrows per user

## 📋 Contract Functions

### Core Operations

#### `create-escrow`
Creates a new parcel escrow with verification code generation.
```clarity
(create-escrow recipient amount duration-blocks)
```
- **recipient**: Principal to receive the parcel
- **amount**: STX amount to escrow (minimum 1 STX)
- **duration-blocks**: Blocks until expiration (max 144 blocks)

#### `confirm-delivery`
Confirms delivery using verification code (QR scan/OTP).
```clarity
(confirm-delivery escrow-id verification-code)
```
- **escrow-id**: Unique escrow identifier
- **verification-code**: 32-byte verification hash

#### `request-refund`
Requests refund after escrow expiration.
```clarity
(request-refund escrow-id)
```

### Management Functions

#### `cancel-escrow`
Cancel escrow within 6 blocks of creation.
```clarity
(cancel-escrow escrow-id)
```

#### `extend-escrow`
Extend escrow duration before expiration.
```clarity
(extend-escrow escrow-id additional-blocks)
```

#### `update-verification-code`
Generate new verification code.
```clarity
(update-verification-code escrow-id)
```

### Read-Only Functions

#### `get-escrow`
Retrieve escrow details.
```clarity
(get-escrow escrow-id)
```

#### `get-user-escrows`
Get all escrow IDs for a user.
```clarity
(get-user-escrows user-principal)
```

#### `is-escrow-expired`
Check if escrow has expired.
```clarity
(is-escrow-expired escrow-id)
```

#### `calculate-fee`
Calculate platform fee for amount.
```clarity
(calculate-fee amount)
```

## 🔧 Admin Functions

#### `set-platform-fee-rate`
Update platform fee rate (owner only).
```clarity
(set-platform-fee-rate new-rate)
```

#### `set-min-escrow-amount`
Set minimum escrow amount (owner only).
```clarity
(set-min-escrow-amount new-amount)
```

#### `emergency-release`
Emergency fund release (owner only).
```clarity
(emergency-release escrow-id to-recipient)
```

## 📊 Escrow States

- 🟡 **pending**: Awaiting delivery confirmation
- 🟢 **completed**: Successfully delivered and confirmed
- 🔴 **refunded**: Funds returned to sender
- ⚪ **cancelled**: Cancelled by sender
- 🟠 **emergency-released**: Admin override release

## 💡 Usage Examples

### Creating an Escrow
```clarity
;; Create 5 STX escrow for 50 blocks
(contract-call? .parcel-escrow create-escrow 'ST1RECIPIENT... u5000000 u50)
```

### Confirming Delivery
```clarity
;; Confirm delivery with verification code
(contract-call? .parcel-escrow confirm-delivery u1 0x...)
```

### Requesting Refund
```clarity
;; Request refund after expiration
(contract-call? .parcel-escrow request-refund u1)
```

## ⚙️ Configuration

### Default Settings
- **Platform Fee**: 2.5% (250/10000)
- **Minimum Amount**: 1 STX (1000000 µSTX)
- **Maximum Duration**: 144 blocks (~24 hours)
- **Cancel Window**: 6 blocks (~1 hour)
- **Max Verification Attempts**: 5

### Error Codes
- `u100`: Owner only
- `u101`: Not found  
- `u102`: Unauthorized
- `u103`: Already confirmed
- `u104`: Already refunded
- `u105`: Invalid amount
- `u106`: Expired
- `u107`: Not expired
- `u108`: Invalid verification
- `u109`: Insufficient funds

## 🛠️ Development

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Setup
```bash
git clone <repository>
cd Parcel-Escrow-Contracts
clarinet check
clarinet test
```

### Testing
```bash
clarinet console
clarinet integrate
```

## 🔐 Security Features

- ✅ Verification code generation using cryptographic hashing
- ✅ Time-based expiration with automatic refund eligibility  
- ✅ Rate limiting on verification attempts
- ✅ Owner-only admin functions
- ✅ Comprehensive input validation
- ✅ Reentrancy protection through contract design

## 📄 License

MIT License - feel free to use and modify as needed.

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Make changes with tests
4. Submit pull request

---

Made with ❤️ for secure parcel delivery on Stacks blockchain
