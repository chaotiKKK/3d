; FreeCam3D Windows installer (NSIS 3).
; Per-user install into %LOCALAPPDATA%\Programs -- no elevation, no admin
; prompt. Fully silent-capable with /S (install and uninstall), which is what
; the CI pipeline uses to install and selfcheck the installed app.
; Built by desktop/installer/make-installer.mjs, which passes:
;   -DVERSION=<numeric X.Y.Z>   version resource
;   -DFULLVERSION=<full tag>    display version (may carry a prerelease suffix)
;   -DESTSIZE=<KB>              Add/Remove Programs size estimate
;   -DPKGDIR=<dir>              packaged app (electron-packager output)
;   -DOUTFILE=<path>            installer exe to produce

Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma
CRCCheck on

!define APPNAME "FreeCam3D"
!define PUBLISHER "FreeCam3D"
!define REGPATH "Software\Microsoft\Windows\CurrentVersion\Uninstall\FreeCam3D"

Name "${APPNAME} ${FULLVERSION}"
OutFile "${OUTFILE}"

; 4-part version resource is mandatory (VIProductVersion rejects X.Y.Z).
VIProductVersion "${VERSION}.0"
VIFileVersion "${VERSION}.0"
VIAddVersionKey ProductName "${APPNAME}"
VIAddVersionKey FileVersion "${VERSION}.0"
VIAddVersionKey ProductVersion "${FULLVERSION}"
VIAddVersionKey CompanyName "${PUBLISHER}"
VIAddVersionKey FileDescription "${APPNAME} installer"

InstallDir "$LOCALAPPDATA\Programs\${APPNAME}"
InstallDirRegKey HKCU "${REGPATH}" "InstallLocation"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${PKGDIR}\*.*"

  CreateShortCut "$SMPROGRAMS\${APPNAME}.lnk" "$INSTDIR\FreeCam3D.exe"
  CreateShortCut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\FreeCam3D.exe"

  ; Add/Remove Programs entry (HKCU -- matches the per-user install level).
  WriteRegStr HKCU "${REGPATH}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${REGPATH}" "DisplayVersion" "${FULLVERSION}"
  WriteRegStr HKCU "${REGPATH}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${REGPATH}" "DisplayIcon" "$INSTDIR\FreeCam3D.exe"
  WriteRegStr HKCU "${REGPATH}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${REGPATH}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${REGPATH}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${REGPATH}" "NoModify" 1
  WriteRegDWORD HKCU "${REGPATH}" "NoRepair" 1
  WriteRegDWORD HKCU "${REGPATH}" "EstimatedSize" ${ESTSIZE}

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  RMDir /r "$INSTDIR"
  Delete "$SMPROGRAMS\${APPNAME}.lnk"
  Delete "$DESKTOP\${APPNAME}.lnk"
  DeleteRegKey HKCU "${REGPATH}"
SectionEnd
