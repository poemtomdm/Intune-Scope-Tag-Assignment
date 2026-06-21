# 🏷️ Intune Scope Tag Assignment Tool

> A PowerShell script that bulk-assigns **Role Scope Tags** to Intune-managed apps and configuration profiles across all platforms, using the Microsoft Graph API.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-Beta-orange?logo=microsoft&logoColor=white)
![Platforms](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20iOS%20%7C%20Android-lightgrey?logo=microsoft)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Usage](#-usage)
- [Parameters](#-parameters)
- [Supported Categories & Platforms](#-supported-categories--platforms)
- [How It Works](#-how-it-works)
- [Sample Output](#-sample-output)
- [Known Limitations](#-known-limitations)
- [Troubleshooting](#-troubleshooting)

---

## 🔍 Overview

Managing Role Scope Tags at scale in Microsoft Intune is tedious when done through the portal — this script automates the entire process.

It connects to your tenant using a registered **Entra ID App** and walks you through an interactive menu to select:

1. **What** to tag — Applications or Configuration Profiles
2. **Which platform** — Android, iOS, macOS, or Windows
3. **Which Scope Tag(s)** to assign — one or many, comma-separated

The script then resolves tag names to IDs and bulk-patches every matching object via the Graph API — with a clear per-item result and a summary at the end.

> 🔒 **No credentials are ever hardcoded.** Authentication is handled entirely through parameters at runtime.

---

## ✨ Features

| Feature | Detail |
|---|---|
| 📱 Multi-platform | Android, iOS, macOS, Windows |
| 🗂️ Multiple categories | Apps, Configurations (Settings Catalog, Classic Profiles, Admin Templates) |
| 🔐 Flexible auth | Client Secret, Certificate Thumbprint, or PFX file |
| 📄 Paginated fetching | Handles large tenants with hundreds of apps or policies |
| ⏭️ Smart skipping | Automatically skips types that don't support scope tag assignment via API (e.g. iOS VPP apps) |
| 📊 Run summary | Success / Skipped / Failed counts at the end of every run |

---

## 🧰 Prerequisites

| Requirement | Details |
|---|---|
| **PowerShell** | Version 5.1 or later (PowerShell 7+ recommended) |
| **Microsoft Graph PowerShell SDK** | `Install-Module Microsoft.Graph -Scope CurrentUser` |
| **Entra ID App Registration** | With `DeviceManagementApps.ReadWrite.All`, `DeviceManagementConfiguration.ReadWrite.All`, and `DeviceManagementRBAC.Read.All` (Application permissions, admin consent granted) |
| **Role Scope Tags** | Must already exist in your Intune tenant before running |

---

## 🚀 Usage

The script supports **three authentication methods**. Pick the one that matches how your App Registration is configured.

---

### 🔑 Option 1 — Client Secret

```powershell
.\assignscopetag_allwindowsapps.ps1 `
    -TenantId     "contoso.onmicrosoft.com" `
    -ClientId     "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ClientSecret "your-client-secret-here"
```

---

### 🔐 Option 2 — Certificate Thumbprint

Use this when the certificate is already installed in the local certificate store of the machine running the script.

```powershell
.\assignscopetag_allwindowsapps.ps1 `
    -TenantId              "contoso.onmicrosoft.com" `
    -ClientId              "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CertificateThumbprint "AABBCCDDEEFF00112233445566778899AABBCCDD"
```

---

### 📄 Option 3 — Certificate PFX File

Use this when the certificate is a `.pfx` file on disk rather than installed in the cert store.

```powershell
# With a password-protected PFX
.\assignscopetag_allwindowsapps.ps1 `
    -TenantId            "contoso.onmicrosoft.com" `
    -ClientId            "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CertificatePath     "C:\certs\myapp.pfx" `
    -CertificatePassword (Read-Host -AsSecureString "PFX password")

# Without a password
.\assignscopetag_allwindowsapps.ps1 `
    -TenantId        "contoso.onmicrosoft.com" `
    -ClientId        "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CertificatePath "C:\certs\myapp.pfx"
```

---

## ⚙️ Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-TenantId` | `String` | ✅ Always | Tenant ID or domain name (e.g. `contoso.onmicrosoft.com`) |
| `-ClientId` | `String` | ✅ Always | Application (client) ID of your App Registration |
| `-ClientSecret` | `String` | ✅ *Option 1 only* | The client secret value |
| `-CertificateThumbprint` | `String` | ✅ *Option 2 only* | Thumbprint of the certificate in the local cert store |
| `-CertificatePath` | `String` | ✅ *Option 3 only* | Full path to a `.pfx` certificate file |
| `-CertificatePassword` | `SecureString` | ❌ Optional | Password for the `.pfx` file (Option 3 only, if applicable) |

> ℹ️ Parameter sets are mutually exclusive — you cannot mix auth options in the same command.

---

## 📂 Supported Categories & Platforms

After authenticating, the script presents an **interactive menu**.

### Categories

| # | Category | Status |
|---|---|---|
| 1 | Applications | ✅ Available |
| 2 | Configurations | ✅ Available |
| 3 | Compliance Policies | 🔜 Coming Soon |
| 4 | Windows Platform Scripts | 🔜 Coming Soon |
| 5 | Windows Remediation Scripts | 🔜 Coming Soon |
| 6 | macOS Scripts | 🔜 Coming Soon |
| 7 | macOS Custom Attributes | 🔜 Coming Soon |
| 8 | App Configuration Policies | 🔜 Coming Soon |
| 9 | App Protection Policies | 🔜 Coming Soon |

---

### Platforms & What Gets Fetched

| # | Platform | Applications | Configuration Sources |
|---|---|---|---|
| 1 | 🤖 Android | ✅ All Android app types | Classic profiles + Settings Catalog |
| 2 | 🍎 iOS / iPadOS | ✅ All iOS app types | Classic profiles + Settings Catalog |
| 3 | 🖥️ macOS | ✅ All macOS app types | Classic profiles + Settings Catalog |
| 4 | 🪟 Windows | ✅ All Windows app types | Classic profiles + Settings Catalog + Admin Templates |

---

## 🔄 How It Works

```
 1. Connect       →  Authenticate to Microsoft Graph with your chosen method
        ↓
 2. Menu          →  Select Category (Apps / Configs) and Platform
        ↓
 3. Tag Input     →  Enter one or more Scope Tag names (comma-separated)
        ↓
 4. Resolve Tags  →  Look up each tag name and retrieve its Intune ID
        ↓
 5. Fetch Items   →  Pull all matching apps / policies (paginated, multi-endpoint)
        ↓
 6. PATCH Items   →  Assign roleScopeTagIds to each object via Graph API
        ↓
 7. Summary       →  Print Success / Skipped / Failed counts
```

> ⚠️ **Important:** The PATCH operation **replaces** the entire `roleScopeTagIds` array. If an item already has scope tags that are not included in your input, they will be removed. Always provide all desired tags in a single run.

---

## 📤 Sample Output

```
Connecting to Microsoft Graph...
Connected to Microsoft Graph successfully.

============================================
  Intune Scope Tag Assignment Tool
============================================

What would you like to assign scope tags to?
  1 - Applications
  2 - Configurations
  ...

Enter category number (1-9): 2

Available platforms:
  1 - Android
  2 - iOS
  3 - macOS
  4 - Windows

Enter platform number (1-4): 2
Selected platform: iOS

Enter Role Scope Tag name(s) to assign (comma-separated): EMEA,MobileDevices

Looking up IDs for scope tag(s): EMEA, MobileDevices
  Found: 'EMEA'          ->  ID: 5
  Found: 'MobileDevices' ->  ID: 12

Fetching iOS Configurations from Intune...
  [1/2] Classic profiles (deviceConfigurations)...
  Page 1 — 38 item(s) retrieved...
  [2/2] Settings Catalog (configurationPolicies)...
  Page 1 — 17 item(s) retrieved...
Found 55 configuration(s) for platform: iOS

Assigning scope tags...

  [OK]   IOS - Device Restrictions - Corporate
  [OK]   IOS - Email Profile - Corporate
  [SKIP] Acme VPP App (#microsoft.graph.iosVppApp) — VPP apps must have scope tags set at the VPP token level
  [FAIL] Some App – Insufficient privileges to complete the operation

============================================
  Done!
  Category   : Configurations
  Platform   : iOS
  Scope Tags : EMEA, MobileDevices
  Success    : 53 configuration(s)
  Skipped    : 1 configuration(s)
  Failed     : 1 configuration(s)
============================================
```

---

## ⚠️ Known Limitations

| Limitation | Detail |
|---|---|
| **iOS & macOS VPP Apps** | Scope tags on VPP apps must be configured at the **VPP token level** in the Intune portal. These are automatically detected and skipped with a `[SKIP]` message. |
| **Tags are replaced, not merged** | The PATCH replaces the full `roleScopeTagIds` array. Include all desired tags in a single run to avoid removing existing ones. |
| **Graph Beta API** | This script uses the `/beta` endpoint. Microsoft may change beta behaviours without notice. |
| **Client-side filtering** | Some endpoints (e.g. `deviceConfigurations`) don't support server-side OData filtering by platform, so all records are fetched and filtered locally — this may be slower in very large tenants. |

---

## 🛠️ Troubleshooting

<details>
<summary><strong>❌ "Failed to connect to Microsoft Graph"</strong></summary>

- Double-check your `-TenantId`, `-ClientId`, and credential values
- Ensure admin consent has been granted for all API permissions
- Check that your client secret has not expired, or that your certificate is valid

</details>

<details>
<summary><strong>❌ Scope Tag shows as "NOT FOUND"</strong></summary>

- Tag names are **case-sensitive** — match the name exactly as it appears in Intune
- Verify the tag exists: **Intune → Tenant administration → Roles → Scope tags**

</details>

<details>
<summary><strong>❌ "[FAIL]" on specific items</strong></summary>

- Read the error message printed next to `[FAIL]` — it contains the Graph API error detail
- Confirm your App Registration has `ReadWrite` (not just `Read`) permissions
- Some item types may not support scope tag assignment via the Graph API

</details>

<details>
<summary><strong>⚠️ Certificate not found when using -CertificateThumbprint</strong></summary>

Make sure the certificate is installed in the **CurrentUser\My** or **LocalMachine\My** store:

```powershell
# Check CurrentUser store
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq "YOUR_THUMBPRINT" }

# Check LocalMachine store
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq "YOUR_THUMBPRINT" }
```

</details>

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

> **Disclaimer:** This script makes live changes to your Intune tenant. Always validate in a non-production environment before running against production. The authors accept no responsibility for unintended configuration changes.
