# 🏥 IPRCM - Immutable Patient Record Consent Manager

A blockchain-based smart contract system for managing patient healthcare record access permissions using Clarity on the Stacks blockchain.

## 📋 Overview

IPRCM enables patients to have full control over their healthcare data by managing consent permissions for healthcare providers. The system ensures transparency, immutability, and patient autonomy in healthcare data access.

## ✨ Features

- 👤 **Patient Registration**: Secure patient registration system
- 🏥 **Healthcare Provider Registration**: Verified provider onboarding  
- 📄 **Patient Record Management**: Immutable record storage with cryptographic hashes
- ✅ **Granular Consent Management**: Grant/revoke access permissions per provider and record type
- ⏰ **Time-based Consent**: Optional expiration dates for temporary access
- 🔍 **Access Verification**: Real-time consent checking for providers
- 📊 **Audit Trail**: Complete history of all consent changes

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation

```bash
git clone <repository-url>
cd immutable-patient-record-consent-manager
clarinet check
```

## 📖 Usage Guide

### For Patients 👥

#### 1. Register as Patient
```clarity
(contract-call? .IPRCM register-patient "John Doe")
```

#### 2. Add Medical Records
```clarity
(contract-call? .IPRCM add-patient-record "blood-test" 0x1234567890abcdef...)
```

#### 3. Grant Access to Provider
```clarity
;; Grant general access
(contract-call? .IPRCM grant-consent 'SP1PROVIDER123... none none)

;; Grant access to specific record type with expiration
(contract-call? .IPRCM grant-consent 'SP1PROVIDER123... (some "blood-test") (some u1000))
```

#### 4. Revoke Access
```clarity
;; Revoke specific consent by ID
(contract-call? .IPRCM revoke-consent u1)

;; Revoke all consents for a provider
(contract-call? .IPRCM revoke-all-consents 'SP1PROVIDER123...)
```

### For Healthcare Providers 🏥

#### 1. Register as Provider
```clarity
(contract-call? .IPRCM register-provider "City Hospital" "LIC123456")
```

#### 2. Check Access Permissions
```clarity
(contract-call? .IPRCM has-access 'SP1PATIENT123... 'SP1PROVIDER123... (some "blood-test"))
```

#### 3. View Patient Records (if authorized)
```clarity
(contract-call? .IPRCM get-record-info u1)
```

### For Contract Owner 👑

#### Verify Providers
```clarity
(contract-call? .IPRCM verify-provider 'SP1PROVIDER123...)
```

## 🔧 API Reference

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `register-patient` | Register a new patient | `name: string-ascii` |
| `register-provider` | Register a healthcare provider | `name: string-ascii, license-number: string-ascii` |
| `verify-provider` | Verify a provider (owner only) | `provider: principal` |
| `add-patient-record` | Add a new medical record | `record-type: string-ascii, record-hash: buff` |
| `grant-consent` | Grant access permission | `provider: principal, record-type: optional string-ascii, expires-at: optional uint` |
| `revoke-consent` | Revoke specific consent | `consent-id: uint` |
| `revoke-all-consents` | Revoke all consents for provider | `provider: principal` |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `has-access` | Check if provider has access | `bool` |
| `get-patient-info` | Get patient details | `patient-info` |
| `get-provider-info` | Get provider details | `provider-info` |
| `get-record-info` | Get record details | `record-info` |
| `get-consent-info` | Get consent details | `consent-info` |
| `is-consent-active` | Check if consent is currently active | `bool` |

## 🛡️ Security Features

- ✅ **Access Control**: Only patients can manage their own consents
- ✅ **Provider Verification**: Only verified providers can receive consent
- ✅ **Immutable Records**: All records and consent changes are permanent
- ✅ **Time-based Access**: Support for temporary access permissions
- ✅ **Granular Permissions**: Consent can be specific to record types

## ⚠️ Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u100 | `ERR_UNAUTHORIZED` | Unauthorized access attempt |
| u101 | `ERR_NOT_FOUND` | Resource not found |
| u102 | `ERR_ALREADY_EXISTS` | Resource already exists |
| u103 | `ERR_INVALID_INPUT` | Invalid input parameters |
| u104 | `ERR_CONSENT_EXPIRED` | Consent has expired |
| u105 | `ERR_CONSENT_REVOKED` | Consent has been revoked |

## 🧪 Testing

Run the test suite:

```bash
clarinet test
```

## 📄 License

This project is licensed under the MIT License.

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📞 Support

For questions or support, please open an issue on GitHub.

---

Built with ❤️ for healthcare data privacy and patient autonomy.
