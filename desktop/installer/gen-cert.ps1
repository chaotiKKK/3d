# Generates the local self-signed code-signing certificate (test-quality,
# like the APK's debug keystore) and exports it as PFX for sign.ps1.
# Usage: powershell -NoProfile -File gen-cert.ps1 -OutPfx <path> [-Password <pw>]
param(
  [Parameter(Mandatory = $true)][string]$OutPfx,
  [string]$Password = 'freecam3d'
)
$ErrorActionPreference = 'Stop'

$existing = Get-ChildItem Cert:\CurrentUser\My |
  Where-Object { $_.FriendlyName -eq 'FreeCam3D Code Signing (self-signed)' -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
  Sort-Object NotAfter -Descending | Select-Object -First 1

if ($existing) {
  Write-Output "reusing existing cert $($existing.Thumbprint) (valid until $($existing.NotAfter.ToString('yyyy-MM-dd')))"
  $cert = $existing
} else {
  $cert = New-SelfSignedCertificate -Type CodeSigningCert `
    -Subject 'CN=FreeCam3D, O=FreeCam3D, C=DE' `
    -KeyUsage DigitalSignature `
    -FriendlyName 'FreeCam3D Code Signing (self-signed)' `
    -CertStoreLocation Cert:\CurrentUser\My `
    -NotAfter (Get-Date).AddDays(730)
  Write-Output "created new cert $($cert.Thumbprint) (valid until $($cert.NotAfter.ToString('yyyy-MM-dd')))"
}

$pw = ConvertTo-SecureString $Password -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath $OutPfx -Password $pw | Out-Null
Write-Output "PFX written: $OutPfx"
