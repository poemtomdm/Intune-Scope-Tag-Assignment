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
- [App Registration Setup](#-app-registration-setup)
- [Authentication Methods](#-authentication-methods)
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

Before running the script, ensure you have the following in place:

| Requirement | Details |
|---|---|
| **PowerShell** | Version 5.1 or later (PowerShell 7+ recommended) |
| **Microsoft Graph PowerShell SDK** | `Install-Module Microsoft.Graph -Scope CurrentUser` |
| **Entra ID App Registration** | With the correct API permissions (see below) |
| **Role Scope Tags** | Must already exist in your Intune tenant before running |

### Install the required module

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

> If you're on a managed machine without internet access, download and install the module offline, or ask your IT administrator.

---

## 🔑 App Registration Setup

You need an **App Registration** in Microsoft Entra ID with the following configuration.

### Step 1 — Create the App Registration

1. Go to [Entra ID → App Registrations](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)
2. Click **New registration**
3. Name it something descriptive (e.g. `Intune-ScopeTag-Tool`)
4. Set **Supported account types** → _Accounts in this organizational directory only_
5. Click **Register**

> 📝 After registering, copy the **Application (client) ID** and the **Directory (tenant) ID** — you'll need them as script parameters.

---

### Step 2 — Add API Permissions

Go to **API permissions → Add a permission → Microsoft Graph → Application permissions** and add:

| Permission | Purpose |
|---|---|
| `DeviceManagementApps.ReadWrite.All` | Read and patch mobile apps |
| `DeviceManagementConfiguration.ReadWrite.All` | Read and patch configuration profiles |
| `DeviceManagementRBAC.Read.All` | Look up Role Scope Tag names and IDs |

After adding, click **✅ Grant admin consent for [your tenant]**.

---

### Step 3 — Choose a Credential Type

#### 🔑 Option A — Client Secret
1. Go to **Certificates & secrets → Client secrets → New client secret**
2. Set a description and expiry, then click **Add**
3. Copy the **Value** immediately — it will not be shown again

#### 🔐 Option B — Certificate
1. Go to **Certificates & secrets → Certificates → Upload certificate**
2. Upload your `.cer` or `.pem` public key
3. Note the **Thumbprint** displayed after upload — you'll use it as a parameter

---

## 🔐 Authentication Methods

The script uses **PowerShell parameter sets** to enforce that exactly one auth method is provided. No mixing, no hardcoding.

| Method | Parameter Set | Recommended For |
|---|---|---|
| Client Secret | `ClientSecret` *(default)* | Quick setup, testing, automation pipelines |
| Certificate (cert store) | `CertThumbprint` | Production — cert installed locally |
| Certificate (.pfx file) | `CertFile` | Production — portable cert file |

> ✅ Certificate-based auth is recommended for production as it avoids secret expiry issues and is considered more secure.

---

## 🚀 Usage

### Client Secret

```powershell
.\IntuneScopeTagAssignment.ps1 `
    -TenantId     "contoso.onmicrosoft.com" `
    -ClientId     "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ClientSecret "your-client-secret-here"
```

---

### Certificate — Thumbprint (from local cert store)

> The certificate must be installed in the **CurrentUser** or **LocalMachine** certificate store on the machine running the script.

```powershell
.\IntuneScopeTagAssignment.ps1 `
    -TenantId              "contoso.onmicrosoft.com" `
    -ClientId              "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CertificateThumbprint "AABBCCDDEEFF00112233445566778899AABBCCDD"
```

---

### Certificate — PFX File

```powershell
.\IntuneScopeTagAssignment.ps1 `
    -TenantId            "contoso.onmicrosoft.com" `
    -ClientId            "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CertificatePath     "C:\certs\myapp.pfx" `
    -CertificatePassword (Read-Host -AsSecureString "PFX password")
```

> 💡 Omit `-CertificatePassword` if your `.pfx` file has no password set.

---

## ⚙️ Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-TenantId` | `String` | ✅ Always | Tenant ID or domain name (e.g. `contoso.onmicrosoft.com`) |
| `-ClientId` | `String` | ✅ Always | Application (client) ID of your App Registration |
| `-ClientSecret` | `String` | ✅ *ClientSecret set* | The client secret value from the App Registration |
| `-CertificateThumbprint` | `String` | ✅ *CertThumbprint set* | Thumbprint of a certificate installed in the local cert store |
| `-CertificatePath` | `String` | ✅ *CertFile set* | Full path to a `.pfx` certificate file |
| `-CertificatePassword` | `SecureString` | ❌ Optional | Password for the `.pfx` file (only used with `-CertificatePath`) |

---

## 📂 Supported Categories & Platforms

After connecting, the script presents an **interactive menu**.

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

**Pagination** — All Graph API calls follow `@odata.nextLink` automatically, so large environments with hundreds of items are fully covered.

**PATCH logic** — The script builds the correct body per endpoint:
- `mobileApps` and `deviceConfigurations` → body **includes** `@odata.type` (required by Graph)
- `configurationPolicies` and `groupPolicyConfigurations` → body **omits** `@odata.type` (not accepted by Graph)

> ⚠️ **Important:** The PATCH operation **replaces** the entire `roleScopeTagIds` array. If an item already has scope tags that you do not include in your input, they will be removed. Always provide all desired tags in a single run.

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
  Found: 'EMEA'         ->  ID: 5
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
| **iOS & macOS VPP Apps** | Scope tags on VPP apps must be configured at the **VPP token level** in the Intune portal. These are automatically detected and skipped with a clear `[SKIP]` message. |
| **Tags are replaced, not merged** | The PATCH replaces the full `roleScopeTagIds` array. Include all desired tags in a single run to avoid removing existing ones. |
| **Graph Beta API** | This script uses the `/beta` endpoint. Microsoft may change beta behaviours without notice. |
| **Client-side filtering** | Some endpoints (e.g. `deviceConfigurations`) don't support server-side OData filtering by platform, so all records are fetched and filtered locally — this may be slower in very large tenants. |

---

## 🛠️ Troubleshooting

<details>
<summary><strong>❌ "Failed to connect to Microsoft Graph"</strong></summary>

- Double-check your `-TenantId`, `-ClientId`, and credential values
- Ensure **admin consent** has been granted for all API permissions in the App Registration
- Check that your client secret has not expired, or that your certificate is valid and trusted

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
- Some item types may not support scope tag assignment at all via the Graph API

</details>

<details>
<summary><strong>⚠️ "Module not found" or Import errors</strong></summary>

Run the following to install the Microsoft Graph module:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

If you are on a managed machine, you may need to run PowerShell as **Administrator** or install to the `AllUsers` scope:

```powershell
Install-Module Microsoft.Graph -Scope AllUsers -Force
```

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
