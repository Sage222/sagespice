# ============================================================
#  Connect-ProxmoxVM.ps1
#  Fetches a fresh SPICE .vv file from Proxmox and launches
#  it in virt-viewer (remote-viewer) automatically.
# ============================================================

# ── CONFIG ───────────────────────────────────────────────────
$PROXMOX_HOST = "x.x.x.x"          # Your Proxmox IP or hostname
$PROXMOX_PORT = "8006"				#usually 8006
$NODE         = "pve"        # Your Proxmox node name
$VMID         = "100"                # Your VM ID
$USERNAME     = "root@pam"           # Proxmox username (user@realm)
$PASSWORD     = "password"      # Proxmox password

# Path to remote-viewer.exe (adjust if installed elsewhere)
$REMOTE_VIEWER = "C:\Program Files\VirtViewer v11.0-256\bin\remote-viewer.exe"

# Where to save the .vv file
$VV_FILE = "$env:TEMP\proxmox-spice.vv"
# ─────────────────────────────────────────────────────────────

# Skip TLS certificate validation (self-signed Proxmox certs)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$BASE_URL = "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json"

# ── STEP 1: Authenticate and get ticket ──────────────────────
Write-Host "[1/4] Authenticating to Proxmox..." -ForegroundColor Cyan

try {
    $authResp = Invoke-RestMethod -Method Post `
                    -Uri "$BASE_URL/access/ticket" `
                    -Body @{ username = $USERNAME; password = $PASSWORD }

    $ticket = $authResp.data.ticket
    $csrf   = $authResp.data.CSRFPreventionToken
} catch {
    Write-Host "[ERROR] Authentication failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "        Authenticated OK." -ForegroundColor Green

# ── STEP 2: Build session with auth cookie ───────────────────
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$cookie  = New-Object System.Net.Cookie
$cookie.Name   = "PVEAuthCookie"
$cookie.Value  = $ticket
$cookie.Domain = $PROXMOX_HOST
$session.Cookies.Add($cookie)

$headers = @{ "CSRFPreventionToken" = $csrf }

# ── STEP 3: Wake up display channels via vncproxy ────────────
# This mimics opening the Proxmox console and activates all
# SPICE display heads on the VM before we request the ticket.
Write-Host "[2/4] Waking up VM display channels..." -ForegroundColor Cyan

try {
    Invoke-RestMethod -Method Post `
        -Uri "$BASE_URL/nodes/$NODE/qemu/$VMID/vncproxy" `
        -WebSession $session `
        -Headers $headers `
        -ContentType "application/x-www-form-urlencoded" | Out-Null
} catch {
    Write-Host "[WARN] vncproxy wake-up call failed (VM may already be ready): $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

# ── STEP 4: Fetch SPICE ticket ───────────────────────────────
Write-Host "[3/4] Fetching SPICE ticket for VM $VMID..." -ForegroundColor Cyan

try {
    $spiceResp = Invoke-RestMethod -Method Post `
                    -Uri "$BASE_URL/nodes/$NODE/qemu/$VMID/spiceproxy" `
                    -WebSession $session `
                    -Headers $headers `
                    -Body @{ proxy = $PROXMOX_HOST } `
                    -ContentType "application/x-www-form-urlencoded"

    $spice = $spiceResp.data
} catch {
    Write-Host "[ERROR] Could not get SPICE config. Is the VM running?" -ForegroundColor Red
    Write-Host "        $_" -ForegroundColor Red
    exit 1
}

# ── STEP 5: Write .vv file ────────────────────────────────────
Write-Host "[4/4] Writing .vv file and launching virt-viewer..." -ForegroundColor Cyan

# Convert to hashtable for safe key lookup
$spiceHash = @{}
foreach ($prop in $spice.PSObject.Properties) {
    $spiceHash[$prop.Name] = $prop.Value
}

# Exact field order matching the working Proxmox-generated .vv file
$orderedFields = @(
    "secure-attention", "title", "host", "host-subject",
    "toggle-fullscreen", "proxy", "type", "tls-port", "port",
    "release-cursor", "password", "ca", "delete-this-file"
)

$fileLines = New-Object System.Collections.Generic.List[string]
$fileLines.Add("[virt-viewer]")

foreach ($field in $orderedFields) {
    if ($spiceHash.ContainsKey($field)) {
        $fileLines.Add("$field=$($spiceHash[$field])")
    }
}

# Append any extra fields not in our ordered list
foreach ($key in $spiceHash.Keys) {
    if ($orderedFields -notcontains $key) {
        $fileLines.Add("$key=$($spiceHash[$key])")
    }
}

# LF line endings, single trailing newline — matches Proxmox native format
$content = ($fileLines -join "`n") + "`n"
[System.IO.File]::WriteAllText($VV_FILE, $content, [System.Text.Encoding]::ASCII)

# ── Launch virt-viewer ────────────────────────────────────────
if (Test-Path $REMOTE_VIEWER) {
    Start-Process -FilePath $REMOTE_VIEWER -ArgumentList $VV_FILE
    Write-Host "        virt-viewer launched. Enjoy your VM!" -ForegroundColor Green
} else {
    Write-Host "[WARN] remote-viewer.exe not found at:" -ForegroundColor Yellow
    Write-Host "       $REMOTE_VIEWER" -ForegroundColor Yellow
    Write-Host "       .vv file saved to: $VV_FILE" -ForegroundColor Yellow
    Write-Host "       Open it manually with virt-viewer." -ForegroundColor Yellow
}
