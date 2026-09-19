# Authenticode-signs one exe with the given PFX and verifies the signature
# embedded correctly (SignerCertificate present + thumbprint match).
#
# Trust note: like the APK's debug keystore, a self-signed cert produces a
# structurally valid signature that shows "unknown publisher" on machines
# without the cert in their trust store. CI installs with /S regardless.
param(
  [Parameter(Mandatory = $true)][string]$PfxPath,
  [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PfxPassword,
  [Parameter(Mandatory = $true)][string]$TargetExe
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PfxPath)) { throw "PFX not found: $PfxPath" }
if (-not (Test-Path $TargetExe)) { throw "target not found: $TargetExe" }

$cert = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation Cert:\CurrentUser\My `
  -Password (ConvertTo-SecureString $PfxPassword -AsPlainText -Force)
# Compare by OID, not FriendlyName -- the friendly name is localized
# ('Code Signing' on EN, 'Codesignatur' on DE Windows) and, on PS 5.1,
# the element's .Value is empty; the dotted OID lives in .ObjectId
# (verified against a real cert on DE Windows / PS 5.1).
$CODESIGNING_EKU = '1.3.6.1.5.5.7.3.3'
$ekus = @($cert.EnhancedKeyUsageList | ForEach-Object {
  if ($_.ObjectId) { [string]$_.ObjectId } elseif ($_.Value) { [string]$_.Value } else { $_.FriendlyName }
})
if ($ekus -notcontains $CODESIGNING_EKU) {
  throw "certificate has no Code Signing EKU ($CODESIGNING_EKU) - got: $($ekus -join ', ')"
}

# Timestamp so the signature outlives the certificate; self-signed certs are
# short-lived, so a timestamp failure is only a warning.
try {
  Set-AuthenticodeSignature -FilePath $TargetExe -Certificate $cert `
    -TimeStampServer 'http://timestamp.digicert.com' | Out-Null
} catch {
  Write-Warning "timestamping failed ($($_.Exception.Message)) -- signing without timestamp"
  Set-AuthenticodeSignature -FilePath $TargetExe -Certificate $cert | Out-Null
}

$sig = $null
for ($i = 0; $i -lt 3; $i++) {
  if ($i -gt 0) { Start-Sleep -Seconds (3 * $i) }
  $sig = Get-AuthenticodeSignature -FilePath $TargetExe
  if ($sig.SignerCertificate) { break }
  Write-Output ("verify attempt " + ($i + 1) + ": no signer yet (" + $sig.Status + ") - chain may still be cold")
}
if (-not $sig -or -not $sig.SignerCertificate) {
  throw "signature missing after signing: $($sig.Status) - $($sig.StatusMessage)"
}
if ($sig.SignerCertificate.Thumbprint -ne $cert.Thumbprint) {
  throw "signature thumbprint mismatch: $($sig.SignerCertificate.Thumbprint) != $($cert.Thumbprint)"
}
Write-Output "SIGNED $TargetExe"
Write-Output "  cert  $($cert.Subject) thumbprint $($cert.Thumbprint)"
Write-Output "  state $($sig.Status): $($sig.StatusMessage)"
if ($sig.Status -ne 'Valid') {
  Write-Output ("  note  self-signed root is not in the machine trust store - status " + $sig.Status + " here is expected (like the APK debug keystore)")
}
