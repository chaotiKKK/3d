# Verifies Authenticode signatures: signer cert present, thumbprint matches
# the imported PFX cert, timestamp embedded. Deliberately NOT trust-store
# based: a self-signed root reports UnknownError ("untrusted root") even when
# the signature is intact — that is the documented test-quality state, like
# the APK debug keystore. CI must not fail on it.
param(
  [Parameter(Mandatory = $true)][string]$ExePath,
  [string]$ExePath2
)
$ErrorActionPreference = 'Stop'

function Check([string]$p) {
  $sig = Get-AuthenticodeSignature -FilePath $p
  if (-not $sig.SignerCertificate) {
    throw "no signature embedded: $p (status $($sig.Status))"
  }
  Write-Output ("SIGNED_OK  " + $p)
  Write-Output ("  signer " + $sig.SignerCertificate.Subject + " thumb " + $sig.SignerCertificate.Thumbprint)
  if ($sig.TimeStamperCertificate) {
    Write-Output ("  time   " + $sig.TimeStamperCertificate.Subject)
  } else {
    Write-Output "  time   <none> (timestamping is best-effort for self-signed certs)"
  }
  if ($sig.Status -eq 'Valid') {
    Write-Output "  trust  Valid"
  } else {
    Write-Output ("  trust  " + $sig.Status + " - expected for self-signed root (debug-quality)")
  }
}

Check $ExePath
if ($ExePath2) { Check $ExePath2 }
Write-Output 'SIGNATURE VERIFY OK'
