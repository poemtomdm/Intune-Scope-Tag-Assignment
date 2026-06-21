# ============================================================
#  SCRIPT   : Assign-IntuneScopeTags.ps1
#  VERSION  : 2.0
#  AUTHOR   : Tom Machado
#  CREATED  : 2026-06-19
#  UPDATED  : 2026-06-21
# ============================================================
#
#  DESCRIPTION
#  -----------
#  This interactive script assigns one or more Intune Role Scope Tags
#  to a bulk set of Intune objects (Applications or Device Configuration
#  profiles) for a given platform (Android, iOS, macOS, Windows).
#
#  The script will:
#    1. Connect to Microsoft Graph using app-only authentication
#       (client secret or certificate).
#    2. Prompt the user to choose a category (Applications or Configurations)
#       and a platform (Android, iOS, macOS, Windows).
#    3. Prompt for one or more Scope Tag names and resolve them to IDs.
#    4. Fetch all matching Intune objects from the relevant Graph API
#       endpoint(s) for the chosen platform and category.
#    5. PATCH each object via Graph API to assign the resolved Scope Tag IDs,
#       overwriting any previously assigned tags with the new set.
#    6. Print a summary of successes, skips, and failures.
#
#  IMPORTANT NOTES
#  ---------------
#  - Scope tags are OVERWRITTEN (not appended). If an object already has
#    tags assigned, they will be replaced by the tags provided at runtime.
#    To preserve existing tags, retrieve them first and merge before patching.
#  - iOS VPP apps (volume-purchased) cannot have scope tags assigned via
#    the Graph API. They must be managed at the VPP token level in Intune.
#  - Some Intune object types (e.g. Update Rings, Domain Join profiles,
#    Enrollment policies) are intentionally excluded from the Configurations
#    fetch as they live under separate Intune blades.
#  - The script targets the Microsoft Graph BETA endpoint, which may change.
#    Review and test after major Intune/Graph updates.
#
#  PREREQUISITES
#  -------------
#  - PowerShell 7+ (recommended) or Windows PowerShell 5.1
#  - Microsoft.Graph PowerShell SDK installed:
#      Install-Module Microsoft.Graph -Scope CurrentUser
#  - An Entra ID (Azure AD) App Registration with:
#      * Application permissions (NOT delegated):
#          - DeviceManagementApps.ReadWrite.All
#          - DeviceManagementConfiguration.ReadWrite.All
#      * Admin consent granted for the above permissions
#  - Authentication: either a Client Secret or a Certificate associated
#    with the App Registration (see usage examples below)
#
#  USAGE EXAMPLES
#  --------------
#  # Client Secret auth:
#  .\IntuneScopeTagAssignment.ps1 `
#      -TenantId     "contoso.onmicrosoft.com" `
#      -ClientId     "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
#      -ClientSecret "your-client-secret-here"
#
#  # Certificate auth (by thumbprint — cert must be in the current user's cert store):
#  .\IntuneScopeTagAssignment.ps1 `
#      -TenantId              "contoso.onmicrosoft.com" `
#      -ClientId              "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
#      -CertificateThumbprint "AABBCCDDEEFF00112233445566778899AABBCCDD"
#
#  # Certificate auth (by .pfx file path):
#  .\IntuneScopeTagAssignment.ps1 `
#      -TenantId            "contoso.onmicrosoft.com" `
#      -ClientId            "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
#      -CertificatePath     "C:\certs\myapp.pfx" `
#      -CertificatePassword (Read-Host -AsSecureString "PFX password")
# ============================================================

# Three mutually exclusive parameter sets handle the supported auth methods:
#   'ClientSecret'   — app ID + secret (simplest, less secure for production)
#   'CertThumbprint' — app ID + cert already installed in the Windows cert store
#   'CertFile'       — app ID + .pfx file path (useful on non-Windows or CI pipelines)

[CmdletBinding(DefaultParameterSetName = 'ClientSecret')]
param (
    # ── Identity ──────────────────────────────────────────────────────────────
    [Parameter(Mandatory, HelpMessage = "Azure AD tenant ID or domain name (e.g. contoso.onmicrosoft.com).")]
    [string] $TenantId,

    [Parameter(Mandatory, HelpMessage = "Application (client) ID of the registered app.")]
    [string] $ClientId,

    # ── Auth: Client Secret ───────────────────────────────────────────────────
    [Parameter(Mandatory, ParameterSetName = 'ClientSecret',
               HelpMessage = "Client secret for the registered app.")]
    [string] $ClientSecret,

    # ── Auth: Certificate (thumbprint) ────────────────────────────────────────
    # Use this when the certificate is already imported into the local Windows
    # certificate store (Cert:\CurrentUser\My or Cert:\LocalMachine\My).
    [Parameter(Mandatory, ParameterSetName = 'CertThumbprint',
               HelpMessage = "Thumbprint of the certificate already installed in the local certificate store.")]
    [string] $CertificateThumbprint,

    # ── Auth: Certificate (pfx file) ──────────────────────────────────────────
    # Use this when the certificate is stored as a .pfx file on disk.
    # The file is loaded into memory at runtime — it is NOT imported into the cert store.
    [Parameter(Mandatory, ParameterSetName = 'CertFile',
               HelpMessage = "Path to the .pfx certificate file.")]
    [string] $CertificatePath,

    [Parameter(ParameterSetName = 'CertFile',
               HelpMessage = "Password for the .pfx file (leave empty if the file has no password).")]
    [SecureString] $CertificatePassword
)

#region --- Connection ---
# Connect to Microsoft Graph using app-only (daemon) authentication.
# The Microsoft.Graph SDK handles token acquisition and renewal automatically.
# Connect-MgGraph stores the session context globally for all subsequent
# Invoke-MgGraphRequest calls in this script — no need to pass tokens manually.

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow

try {
    switch ($PSCmdlet.ParameterSetName) {

        'ClientSecret' {
            # Wrap the plain-text secret in a PSCredential object as required
            # by Connect-MgGraph's -ClientSecretCredential parameter.
            $secureSecret          = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
            $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential -ErrorAction Stop
        }

        'CertThumbprint' {
            # The SDK looks up the certificate by thumbprint in the current user's
            # certificate store (Cert:\CurrentUser\My). The cert must already be installed.
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop
        }

        'CertFile' {
            # Load the certificate directly from the .pfx file into an X509Certificate2
            # object. Supports optional password protection on the file.
            $cert = if ($CertificatePassword) {
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    (Resolve-Path $CertificatePath).Path,
                    $CertificatePassword
                )
            } else {
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    (Resolve-Path $CertificatePath).Path
                )
            }
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Certificate $cert -ErrorAction Stop
        }
    }

    Write-Host "Connected to Microsoft Graph successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

#endregion

#region --- Category selection ---
# The user selects WHAT type of Intune object to tag.
# Currently only Applications (1) and Configurations (2) are fully implemented.
# Options 3-9 are placeholders for future functionality and will exit gracefully.

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Intune Scope Tag Assignment Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What would you like to assign scope tags to?" -ForegroundColor Yellow
Write-Host "  1 - Applications"
Write-Host "  2 - Configurations"
Write-Host "  3 - Compliance                   " -NoNewline; Write-Host "(Coming Soon)" -ForegroundColor DarkGray
Write-Host "  4 - Windows Platform Scripts     " -NoNewline; Write-Host "(Coming Soon)" -ForegroundColor DarkGray
Write-Host "  5 - Windows Remediation Scripts  " -NoNewline; Write-Host "(Coming Soon)" -ForegroundColor DarkGray
Write-Host "  6 - macOS Scripts                " -NoNewline; Write-Host "(Coming Soon)" -ForegroundColor DarkGray
Write-Host "  7 - macOS Custom Attributes      " -NoNewline; Write-Host "(Coming Soon)" -ForegroundColor DarkGray
Write-Host "  8 - App Configuration Policies   " -NoNewline; Write-Host "(Coming Soon)" -ForegroundColor DarkGray
Write-Host "  9 - App Protection Policies      " -NoNewline; Write-Host "(Coming Soon)" -ForegroundColor DarkGray
Write-Host ""

$categoryChoice = Read-Host "Enter category number (1-9)"

switch ($categoryChoice) {
    "1" { $categoryLabel = "Applications" }
    "2" { $categoryLabel = "Configurations" }
    { $_ -in "3","4","5","6","7","8","9" } {
        # Map the choice number to a friendly label for the message
        $categoryNames = @{
            "3" = "Compliance"
            "4" = "Windows Platform Scripts"
            "5" = "Windows Remediation Scripts"
            "6" = "macOS Scripts"
            "7" = "macOS Custom Attributes"
            "8" = "App Configuration Policies"
            "9" = "App Protection Policies"
        }
        Write-Host ""
        Write-Host "  '$($categoryNames[$categoryChoice])' is Coming Soon and not yet available in this version." -ForegroundColor DarkGray
        Write-Host ""
        exit 0
    }
    default {
        Write-Host "Invalid choice. Exiting." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "Selected category: $categoryLabel" -ForegroundColor Green

#endregion

#region --- Platform selection ---
# The user selects WHICH platform's objects to tag.
# Depending on the combination of category + platform, the script will query
# different Graph API endpoints and apply different client-side filters.
# See the "GRAPH API ENDPOINTS USED" section at the top for the full mapping.

Write-Host ""
Write-Host "Available platforms:" -ForegroundColor Yellow
Write-Host "  1 - Android"
Write-Host "  2 - iOS"
Write-Host "  3 - macOS"
Write-Host "  4 - Windows"
Write-Host ""

$platformChoice = Read-Host "Enter platform number (1-4)"

# ─────────────────────────────────────────────────────────────────────────────
# APPLICATIONS
# For apps, a single Graph API URI per platform is sufficient because the
# Graph API supports server-side $filter on the @odata.type property for
# the mobileApps endpoint (unlike deviceConfigurations where @odata.type
# is not filterable server-side).
# ─────────────────────────────────────────────────────────────────────────────
if ($categoryChoice -eq "1") {
    switch ($platformChoice) {
        "1" {
            $platformLabel = "Android"
            # Filters for all Android app types visible in the Intune Apps blade:
            # - androidManagedStoreApp (system + non-system managed store apps)
            # - androidLobApp          (line-of-business / sideloaded APKs)
            # - androidStoreApp        (public Google Play store apps)
            # - managedAndroidStoreApp (MAM-targeted store apps)
            # - managedAndroidLobApp   (MAM-targeted LOB apps)
            # - webApp                 (web link shortcuts)
            # The second condition limits results to assigned apps or LOB apps
            # (excludes unassigned global store apps from cluttering the list).
            $platformUri   = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=((isof(%27microsoft.graph.androidManagedStoreApp%27)%20and%20microsoft.graph.androidManagedStoreApp/isSystemApp%20eq%20true)%20or%20isof(%27microsoft.graph.androidLobApp%27)%20or%20isof(%27microsoft.graph.androidStoreApp%27)%20or%20(isof(%27microsoft.graph.managedAndroidStoreApp%27)%20and%20microsoft.graph.managedApp/appAvailability%20eq%20microsoft.graph.managedAppAvailability%27lineOfBusiness%27)%20or%20isof(%27microsoft.graph.managedAndroidLobApp%27)%20or%20(isof(%27microsoft.graph.managedAndroidStoreApp%27)%20and%20microsoft.graph.managedApp/appAvailability%20eq%20microsoft.graph.managedAppAvailability%27global%27)%20or%20(isof(%27microsoft.graph.androidManagedStoreApp%27)%20and%20microsoft.graph.androidManagedStoreApp/isSystemApp%20eq%20false)%20or%20isof(%27microsoft.graph.webApp%27))%20and%20(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName%20asc"
            $itemNoun      = "app(s)"
            $patchEndpoint = "deviceAppManagement/mobileApps"
            $nameField     = "displayName"
        }
        "2" {
            $platformLabel = "iOS"
            # Filters for all iOS/iPadOS app types:
            # - managedIOSStoreApp  (MAM-targeted App Store apps)
            # - iosLobApp           (LOB .ipa files)
            # - iosStoreApp         (App Store apps)
            # - iosVppApp           (Volume Purchase Program apps — NOTE: scope tags
            #                        cannot be set via API for VPP apps; they are
            #                        skipped in the PATCH loop below)
            # - managedIOSLobApp    (MAM-targeted LOB apps)
            # - webApp              (web link shortcuts)
            # - iOSiPadOSWebClip    (web clip shortcuts on the home screen)
            $platformUri   = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=((isof(%27microsoft.graph.managedIOSStoreApp%27)%20and%20microsoft.graph.managedApp/appAvailability%20eq%20microsoft.graph.managedAppAvailability%27lineOfBusiness%27)%20or%20isof(%27microsoft.graph.iosLobApp%27)%20or%20isof(%27microsoft.graph.iosStoreApp%27)%20or%20isof(%27microsoft.graph.iosVppApp%27)%20or%20isof(%27microsoft.graph.managedIOSLobApp%27)%20or%20(isof(%27microsoft.graph.managedIOSStoreApp%27)%20and%20microsoft.graph.managedApp/appAvailability%20eq%20microsoft.graph.managedAppAvailability%27global%27)%20or%20isof(%27microsoft.graph.webApp%27)%20or%20isof(%27microsoft.graph.iOSiPadOSWebClip%27))%20and%20(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName%20asc"
            $itemNoun      = "app(s)"
            $patchEndpoint = "deviceAppManagement/mobileApps"
            $nameField     = "displayName"
        }
        "3" {
            $platformLabel = "macOS"
            # Filters for all macOS app types:
            # - macOSDmgApp             (.dmg installer packages)
            # - macOSPkgApp             (.pkg installer packages)
            # - macOSLobApp             (LOB apps)
            # - macOSMicrosoftEdgeApp   (Edge browser deployed via Intune)
            # - macOSMicrosoftDefenderApp (Defender for Endpoint)
            # - macOSOfficeSuiteApp     (Microsoft 365 Apps)
            # - macOsVppApp             (Apple VPP apps for macOS)
            # - webApp                  (web link shortcuts)
            # - macOSWebClip            (web clips on the Dock/Launchpad)
            $platformUri   = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=(isof(%27microsoft.graph.macOSDmgApp%27)%20or%20isof(%27microsoft.graph.macOSPkgApp%27)%20or%20isof(%27microsoft.graph.macOSLobApp%27)%20or%20isof(%27microsoft.graph.macOSMicrosoftEdgeApp%27)%20or%20isof(%27microsoft.graph.macOSMicrosoftDefenderApp%27)%20or%20isof(%27microsoft.graph.macOSOfficeSuiteApp%27)%20or%20isof(%27microsoft.graph.macOsVppApp%27)%20or%20isof(%27microsoft.graph.webApp%27)%20or%20isof(%27microsoft.graph.macOSWebClip%27))%20and%20(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName%20asc"
            $itemNoun      = "app(s)"
            $patchEndpoint = "deviceAppManagement/mobileApps"
            $nameField     = "displayName"
        }
        "4" {
            $platformLabel = "Windows"
            # Filters for all Windows app types:
            # - win32LobApp                  (Win32 .intunewin packages)
            # - windowsMicrosoftEdgeApp      (Edge browser deployed via Intune)
            # - windowsStoreApp              (Microsoft Store apps - legacy)
            # - microsoftStoreForBusinessApp (Microsoft Store for Business apps)
            # - officeSuiteApp               (Microsoft 365 Apps for Windows)
            # - windowsUniversalAppX         (UWP / AppX packages)
            # - windowsMobileMSI             (.msi packages)
            # - winGetApp                    (WinGet / new Microsoft Store apps)
            # - webApp                       (web link shortcuts)
            $platformUri   = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=(isof(%27microsoft.graph.win32LobApp%27)%20or%20isof(%27microsoft.graph.windowsMicrosoftEdgeApp%27)%20or%20isof(%27microsoft.graph.windowsStoreApp%27)%20or%20isof(%27microsoft.graph.microsoftStoreForBusinessApp%27)%20or%20isof(%27microsoft.graph.officeSuiteApp%27)%20or%20isof(%27microsoft.graph.windowsUniversalAppX%27)%20or%20isof(%27microsoft.graph.windowsMobileMSI%27)%20or%20isof(%27microsoft.graph.winGetApp%27)%20or%20isof(%27microsoft.graph.webApp%27))%20and%20(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName%20asc"
            $itemNoun      = "app(s)"
            $patchEndpoint = "deviceAppManagement/mobileApps"
            $nameField     = "displayName"
        }
        default {
            Write-Host "Invalid platform choice. Exiting." -ForegroundColor Red
            exit 1
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATIONS
# For configurations, the Graph API does NOT support server-side filtering by
# @odata.type on the deviceConfigurations endpoint. Therefore each platform
# uses one or more $sources objects, each defining:
#   - uri          : the Graph API endpoint to query (paginated)
#   - clientFilter : a PowerShell scriptblock applied locally after fetching
#                    to keep only the relevant platform's profiles
#   - patchEndpoint: the base path used to build the PATCH URI per item
#   - nameField    : the property name holding the display name ('displayName'
#                    for classic profiles, 'name' for configurationPolicies)
# ─────────────────────────────────────────────────────────────────────────────
if ($categoryChoice -eq "2") {
    switch ($platformChoice) {
        "1" {
            $platformLabel = "Android"
            $itemNoun      = "configuration(s)"
            $sources = @(
                # Source 1: Classic device configuration profiles
                # Fetches all profiles then keeps only Android/AOSP types client-side.
                # The @odata.type for Android profiles starts with:
                #   #microsoft.graph.androidDeviceOwner...
                #   #microsoft.graph.androidWorkProfile...
                #   #microsoft.graph.androidGeneral...
                #   #microsoft.graph.androidOmaCp...
                #   #microsoft.graph.aosp...
                [PSCustomObject]@{
                    label         = "Classic profiles (deviceConfigurations)"
                    uri           = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$orderby=displayName asc"
                    clientFilter  = { $_.('@odata.type') -match 'android|Android' }
                    patchEndpoint = "deviceManagement/deviceConfigurations"
                    nameField     = "displayName"
                }
                # Source 2: App configurations & OEMConfig profiles
                # OEMConfig profiles (e.g. Zebra, Samsung Knox) are stored under
                # mobileAppConfigurations, NOT deviceConfigurations.
                # The Intune UI shows them in the Device Configuration blade,
                # but they live in a different API endpoint.
                # WARNING: This endpoint also returns regular Android app config
                # policies (e.g. managed app configs for Teams, Edge, etc.).
                # The current client filter catches ALL android types here,
                # which may over-count if you only want OEMConfig profiles.
                [PSCustomObject]@{
                    label         = "App configurations & OEMConfig (mobileAppConfigurations)"
                    uri           = "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$orderby=displayName asc"
                    clientFilter  = { $_.('@odata.type') -match 'android|Android' }
                    patchEndpoint = "deviceAppManagement/mobileAppConfigurations"
                    nameField     = "displayName"
                }
            )
        }
        "2" {
            $platformLabel = "iOS"
            $itemNoun      = "configuration(s)"
            $sources = @(
                # Source 1: Classic device configuration profiles
                # Keeps profiles whose @odata.type contains 'ios' or 'iOS', which covers:
                #   iosGeneralDeviceConfiguration, iosDeviceFeaturesConfiguration,
                #   iosCustomConfiguration, iosVpnConfiguration, iosWiFiConfiguration,
                #   iosEnterpriseWiFiConfiguration, iosTrustedRootCertificate,
                #   iosPkcsCertificateProfile, iosEasEmailProfileConfiguration,
                #   iosUpdateConfiguration, etc.
                [PSCustomObject]@{
                    label         = "Classic profiles (deviceConfigurations)"
                    uri           = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$orderby=displayName asc"
                    clientFilter  = { $_.('@odata.type') -like '*ios*' -or $_.('@odata.type') -like '*iOS*' }
                    patchEndpoint = "deviceManagement/deviceConfigurations"
                    nameField     = "displayName"
                }
                # Source 2: Settings Catalog policies
                # These are the newer policy type (shown as "Settings catalog" in the UI).
                # Filtered client-side on the 'platforms' property equal to 'iOS'.
                [PSCustomObject]@{
                    label         = "Settings Catalog (configurationPolicies)"
                    uri           = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$orderby=name asc"
                    clientFilter  = { $_.platforms -eq 'iOS' }
                    patchEndpoint = "deviceManagement/configurationPolicies"
                    nameField     = "name"
                }
            )
        }
        "3" {
            $platformLabel = "macOS"
            $itemNoun      = "configuration(s)"
            $sources = @(
                # Source 1: Classic device configuration profiles
                # Keeps profiles whose @odata.type contains 'macOS' or 'macOs',
                # but EXCLUDES macOSSoftwareUpdateConfiguration because those profiles
                # live under the separate "macOS Update Policies" blade in the Intune UI
                # and are not shown in the Device Configuration blade.
                [PSCustomObject]@{
                    label         = "Classic profiles (deviceConfigurations)"
                    uri           = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$orderby=displayName asc"
                    clientFilter  = { ($_.('@odata.type') -match 'macOS|macOs') -and ($_.('@odata.type') -notmatch 'SoftwareUpdate') }
                    patchEndpoint = "deviceManagement/deviceConfigurations"
                    nameField     = "displayName"
                }
                # Source 2: Settings Catalog policies
                # Uses a server-side $filter to return only macOS policies that use
                # 'mdm' or 'appleRemoteManagement' technologies. This matches exactly
                # what the Intune UI shows in the Device Configuration blade for macOS,
                # excluding policies that use other technologies (e.g. pure enrollment).
                [PSCustomObject]@{
                    label         = "Settings Catalog (configurationPolicies)"
                    uri           = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=(platforms eq 'macOS') and (technologies has 'mdm' or technologies has 'appleRemoteManagement')&`$orderby=name asc"
                    clientFilter  = $null   # No additional client-side filter needed — server-side filter is sufficient
                    patchEndpoint = "deviceManagement/configurationPolicies"
                    nameField     = "name"
                }
            )
        }
        "4" {
            $platformLabel = "Windows"
            $itemNoun      = "configuration(s)"
            # Windows configurations span THREE separate Graph API endpoints,
            # each representing a different profile creation experience in the Intune UI.
            $sources = @(
                # Source 1: Classic device configuration profiles
                # Fetches all profiles then keeps Windows types client-side.
                # Note: @odata.type is not server-side filterable on this endpoint.
                # The regex matches all windows* types plus editionUpgrade, sharedPC,
                # and defender types which do not start with 'windows' but are Windows-only.
                [PSCustomObject]@{
                    label        = "Classic profiles (deviceConfigurations)"
                    uri          = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$orderby=displayName asc"
                    clientFilter = { $_.('@odata.type') -match 'windows|editionUpgrade|sharedPC|defender' }
                    patchEndpoint = "deviceManagement/deviceConfigurations"
                    nameField    = "displayName"
                }
                # Source 2: Settings Catalog policies
                # Fetches all policies then keeps Windows ones client-side using
                # the 'platforms' property. This includes all technologies
                # (mdm, enrollment, endpointPrivilegeManagement, microsoftSense).
                [PSCustomObject]@{
                    label        = "Settings Catalog (configurationPolicies)"
                    uri          = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$orderby=name asc"
                    clientFilter = { $_.platforms -eq 'windows10' }
                    patchEndpoint = "deviceManagement/configurationPolicies"
                    nameField    = "name"
                }
                # Source 3: Administrative Templates (Group Policy-style configurations)
                # These are stored in a completely separate endpoint (groupPolicyConfigurations).
                # No client-side filter is needed — all objects in this endpoint are Windows-only.
                [PSCustomObject]@{
                    label        = "Admin Templates (groupPolicyConfigurations)"
                    uri          = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$orderby=displayName asc"
                    clientFilter = $null   # All results are Windows — no filter needed
                    patchEndpoint = "deviceManagement/groupPolicyConfigurations"
                    nameField    = "displayName"
                }
            )
        }
        default {
            Write-Host "Invalid platform choice. Exiting." -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host ""
Write-Host "Selected platform: $platformLabel" -ForegroundColor Green

#endregion

#region --- Scope Tag name input ---
# The user enters one or more Scope Tag NAMES (not IDs).
# Names are comma-separated and trimmed of whitespace.
# The script resolves names to IDs in the next region.

Write-Host ""
$scopeTagInput = Read-Host "Enter Role Scope Tag name(s) to assign (comma-separated for multiple, e.g. TagA,TagB,TagC)"

# Split on comma, trim whitespace from each entry, and drop any empty strings
# (handles trailing commas or extra spaces gracefully)
$scopeTagNames = $scopeTagInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

if ($scopeTagNames.Count -eq 0) {
    Write-Host "No scope tag names provided. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Looking up IDs for scope tag(s): $($scopeTagNames -join ', ')" -ForegroundColor Yellow

#endregion

#region --- Resolve Scope Tag names to IDs ---

$allScopeTagsResponse = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags" `
    -OutputType PSObject

$allScopeTags = $allScopeTagsResponse.value

$resolvedTagIds = @()
$notFound       = @()

foreach ($name in $scopeTagNames) {
    $match = $allScopeTags | Where-Object { $_.displayName -eq $name }
    if ($match) {
        $resolvedTagIds += $match.id
        Write-Host "  Found: '$name'  ->  ID: $($match.id)" -ForegroundColor Green
    } else {
        $notFound += $name
        Write-Host "  NOT FOUND: '$name'" -ForegroundColor Red
    }
}

if ($notFound.Count -gt 0) {
    Write-Host ""
    Write-Host "The following scope tag names were not found and will be skipped:" -ForegroundColor Yellow
    $notFound | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

if ($resolvedTagIds.Count -eq 0) {
    Write-Host ""
    Write-Host "No valid scope tag IDs resolved. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Resolved Scope Tag IDs: $($resolvedTagIds -join ', ')" -ForegroundColor Cyan

#endregion

#region --- Fetch items ---

Write-Host ""
Write-Host "Fetching $platformLabel $categoryLabel from Intune..." -ForegroundColor Yellow

# $allItems entries are hashtables: { item, patchEndpoint, nameField }
$allItems  = @()

Function Get-IntuneItems {
    param($uri, $patchEp, $nameF, $clientFilter)
    $pageCount = 0
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject
        $values   = $response.value
        if ($clientFilter) { $values = $values | Where-Object $clientFilter }
        if ($values.Count -eq 0 -and -not $response.'@odata.nextLink') { break }
        foreach ($v in $values) {
            $script:allItems += [PSCustomObject]@{ item = $v; patchEndpoint = $patchEp; nameField = $nameF }
        }
        $pageCount++
        Write-Host "  Page $pageCount — $($values.Count) item(s) retrieved..." -ForegroundColor DarkGray
        $uri = $response.'@odata.nextLink'
    } while ($uri)
}

if ($sources) {
    $sourceIndex = 0
    foreach ($source in $sources) {
        $sourceIndex++
        Write-Host "  [$sourceIndex/$($sources.Count)] $($source.label)..." -ForegroundColor DarkGray
        Get-IntuneItems -uri $source.uri -patchEp $source.patchEndpoint -nameF $source.nameField -clientFilter $source.clientFilter
    }
} else {
    Get-IntuneItems -uri $platformUri -patchEp $patchEndpoint -nameF $nameField -clientFilter $null
}

Write-Host "Found $($allItems.Count) $itemNoun for platform: $platformLabel" -ForegroundColor Green

#endregion

#region --- Patch items ---

Write-Host ""
Write-Host "Assigning scope tags..." -ForegroundColor Yellow
Write-Host ""

$successCount = 0
$failCount    = 0
$skippedCount = 0
$skippedItems = @()

# OData types that cannot have scope tags assigned via Graph API.
# iOS VPP apps must have scope tags configured in Intune at purchase/sync time.
$skipTypes = @(
    '#microsoft.graph.iosVppApp'
)

foreach ($entry in $allItems) {
    $item     = $entry.item
    $itemId   = $item.id
    $itemName = $item.($entry.nameField)
    $itemType = $item.'@odata.type'   # null for configurationPolicies (not OData-typed)

    # Skip types that do not support scope tag assignment via PATCH
    if ($itemType -and ($skipTypes -contains $itemType)) {
        Write-Host "  [SKIP] $itemName ($itemType) — VPP apps must have scope tags set in Intune at the VPP token level, not via API." -ForegroundColor Yellow
        $skippedCount++
        $skippedItems += $itemName
        continue
    }

    # Build PATCH body — configurationPolicies do not use @odata.type
    if ($itemType) {
        $body = @{
            "@odata.type"     = $itemType
            "roleScopeTagIds" = $resolvedTagIds
        } | ConvertTo-Json
    } else {
        $body = @{
            "roleScopeTagIds" = $resolvedTagIds
        } | ConvertTo-Json
    }

    $patchUri = "https://graph.microsoft.com/beta/$($entry.patchEndpoint)/$itemId"

    try {
        Invoke-MgGraphRequest -Method PATCH -Uri $patchUri -Body $body -ContentType "application/json"
        Write-Host "  [OK] $itemName" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  [FAIL] $itemName – $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

#endregion

#region --- Summary ---

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Done!" -ForegroundColor Cyan
Write-Host "  Category   : $categoryLabel" -ForegroundColor Cyan
Write-Host "  Platform   : $platformLabel" -ForegroundColor Cyan
Write-Host "  Scope Tags : $($scopeTagNames -join ', ')" -ForegroundColor Cyan
Write-Host "  Success    : $successCount $itemNoun" -ForegroundColor Green
Write-Host "  Skipped    : $skippedCount $itemNoun" -ForegroundColor Yellow
Write-Host "  Failed     : $failCount $itemNoun" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "============================================" -ForegroundColor Cyan

if ($skippedItems.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped items (scope tags must be set at the VPP token level in Intune):" -ForegroundColor Yellow
    $skippedItems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

#endregion
