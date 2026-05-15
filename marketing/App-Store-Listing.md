# Kryptos — App Store Listing

Character limits below reflect App Store Connect's current maximums.

---

## App Name (max 30)

**Kryptos — Private Vault** *(25)*

Alternates:
- `Kryptos: Document Vault` *(23)*
- `Kryptos – Secure Vault` *(22)*

## Subtitle (max 30)

**Zero-knowledge document vault** *(30)*

Alternates:
- `Encrypted IDs, cards & notes` *(28)*
- `Your private offline vault` *(26)*

## Promotional Text (max 170, editable without resubmission)

```
Your passports, IDs, cards, and notes - encrypted on-device with AES-256 via Apple CryptoKit. No servers. No subscriptions. Just $1.99 to go Pro.
```
*(159)*

## Description (max 4000)

```
Kryptos is a zero-knowledge personal vault for your most sensitive documents - passports, ID cards, driver's licences, payment cards, API keys, and private notes. Everything is encrypted on your device with AES-GCM (256-bit). We never see your data, and we can't.

ZERO-KNOWLEDGE BY DESIGN
Your vault is sealed with AES-256-GCM using Apple's CryptoKit. The encryption key is stored in the iOS Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly - it never leaves your device. There is no Kryptos server holding your secrets. Even cloud backups upload only opaque, encrypted bytes.

SMART DOCUMENT SCANNING
Snap a passport, a driver's licence, an ID card, or a payment card. On-device VisionKit and Live Text extract the fields automatically. Camera frames never leave your iPhone.

QR CODE CAPTURE AND REGENERATION
Point the camera at any QR code to import its contents. Kryptos can regenerate the same QR from the saved entry whenever you need it.

BEAUTIFUL HERO CARDS
Each document type gets its own purpose-built card UI - passports, driver's licences, credit cards, IDs, notes, API keys, tax numbers - with a scanned attachment rendered as the card itself.

EXPIRY REMINDERS
Add an Expiry field to any entry and Kryptos sends a local notification 30 days, 7 days, and 1 day before it expires. All scheduled offline through local notifications - no cloud dependency.

FACE ID AND TOUCH ID UNLOCK
Lock your vault behind biometric authentication backed by the Secure Enclave.

ENCRYPTED CLOUD BACKUP
Auto-backup your encrypted vault to your choice of iCloud (private CloudKit database) or your own Google Drive:
- Free: hidden Drive AppData folder
- Pro: a visible "KryptosBackups" folder, easier to manage and copy off-device

Neither iCloud nor Google Drive can decrypt the backup. Only your device can.

MULTI-ACCOUNT ISOLATION
Each signed-in account (Sign in with Apple or Google) gets its own fully isolated, separately encrypted vault. Switch accounts without entries leaking between them.

PRICING - SIMPLE AND FAIR
- Free: store up to 10 entries, full features, no ads.
- Kryptos Pro: $1.99 one-time. Unlimited entries, visible Drive backup, priority support, and all future Pro features included.

No subscriptions. No recurring fees. Pay once, own it forever.

WHY KRYPTOS
Most "secure" vaults are convenient because they hold your data on someone else's server. Kryptos picks the harder path: your data stays on your device, encrypted with a key only you control. The trade-off is that we can never reset your vault for you - but it also means no breach, leak, or subpoena exposes your secrets.

PERMISSIONS WE REQUEST
- Camera: to scan documents and QR codes (on-device only)
- Face ID or Touch ID: to unlock your vault
- Notifications: for expiry reminders
- Internet: only for Sign in with Apple or Google, iCloud sync, Drive backup, and App Store purchase verification

WHAT WE DO NOT DO
- Run a server that stores your vault contents
- Show ads or embed advertising SDKs
- Sell, share, or analyse your data
- Hold a copy of your encryption key

Privacy policy: https://kryptos.faizalmzain.com/privacy
Terms and FAQ: https://kryptos.faizalmzain.com/faq
```

## Keywords (max 100 chars total, comma-separated)

```
password,vault,id card,passport,wallet,scanner,encrypt,secure,2fa,nfc,document,note,api,backup
```
*(99)*

Alternates focusing on different segments:
- `vault,password,encrypt,id,passport,license,wallet,secure,private,document,backup,note,2fa,key` *(98)*

## What's New (first release, max 4000)

```
Welcome to Kryptos!

- Zero-knowledge vault encrypted with AES-256-GCM via Apple CryptoKit
- On-device OCR scanning for passports, ID cards, driver's licences, and payment cards
- QR code capture and regeneration
- Face ID and Touch ID unlock backed by the Secure Enclave
- Local expiry reminders (30, 7, and 1 day before)
- Encrypted backup to iCloud private database or your own Google Drive
- Multi-account isolation across Apple and Google sign-in
- Pro unlock: $1.99 one-time, no subscriptions
```

---

## App Store Connect — Metadata

| Field | Value |
|---|---|
| Primary Category | Utilities |
| Secondary Category | Productivity |
| Age Rating | 4+ (no objectionable content) |
| Copyright | © 2026 Faizal Zain |
| Support URL | https://kryptos.faizalmzain.com/faq |
| Marketing URL | https://kryptos.faizalmzain.com |
| Privacy Policy URL | https://kryptos.faizalmzain.com/privacy |
| Routing App Coverage File | not applicable |
| Sign-in required for review? | yes — provide a demo Apple ID *or* mark "no demo account needed" if you ship a "Skip sign-in" review build |

## Pricing

- Tier: Free
- In-App Purchase: `kryptos_pro_upgrade` — Non-Consumable — $1.99 — "Kryptos Pro"

## App Privacy ("Nutrition Label")

Declare in App Store Connect → App Privacy:

**Data Linked to You**
- *Identifiers — User ID*: collected for **App Functionality** (auth identity). Encrypted in transit.
- *Purchases — Purchase history*: collected for **App Functionality** (StoreKit). Encrypted in transit.

**Data Not Collected**
- Contact info beyond optional email shown in Sign in with Apple / Google
- Health, financial, location, contacts, user content (documents/notes/cards), browsing history, search history, identifiers other than user ID, usage data, diagnostics, sensitive info

**Encryption**
- Yes, all transmitted data is encrypted (TLS via URLSession; backup payload is end-to-end encrypted before upload).

## Export Compliance

- Uses only iOS-provided crypto (CryptoKit AES.GCM, Security framework, Keychain, URLSession TLS).
- `ITSAppUsesNonExemptEncryption = false` set in `Kryptos-Info.plist` — qualifies for §740.17(b)(1) exemption. No annual self-classification report required.

## Account Deletion (App Review 5.1.1(v))

Reachable in-app: **Settings → Delete Account** (see `AccountSettingsView.swift`). Deletes all entries, the local encryption key, the cached account session, and cancels all pending expiry reminders. Footer copy directs the user to also delete iCloud/Drive backups for full removal.

## Required Assets — At a glance

| Asset | Size | File |
|---|---|---|
| App Store icon | 1024×1024 PNG (no alpha) | `icon-1024.png` |
| iPhone 6.9" screenshots | 1320×2868 PNG | `screenshots/iphone-6.9/screenshot-{1..5}.png` |
| App Preview video (optional) | 1080×1920 or 1920×1080 mp4 | — |

> The app target is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so iPad screenshots are not required.

## Review Notes (paste into App Store Connect → Notes for Reviewer)

```
Kryptos is a zero-knowledge personal vault. To exercise the full feature set:

1. Sign in with Apple at the lock screen (no demo credentials required).
2. Tap "Add Entry" to create one of each document type. For ID/passport/licence/payment card, optionally tap "Scan document" to test on-device OCR.
3. To test the iCloud backup flow, the device must be signed into iCloud with the same Apple ID; CloudKit private database is used.
4. To test Google Drive backup, tap "Sign in with Google" and grant the requested AppData scope.
5. Pro upgrade ($1.99 non-consumable) is in the Settings sheet. Restore Purchases is also there.
6. Account deletion is at Settings → Delete Account; it wipes the local vault and signs out.

All encryption is via Apple's CryptoKit (AES-256-GCM) with the symmetric key stored in the Keychain. No data leaves the device unencrypted.
```
