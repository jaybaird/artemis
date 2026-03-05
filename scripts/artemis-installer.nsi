; Artemis Windows installer (NSIS)
; Expected defines from build-windows-installer.sh:
;   APP_NAME
;   APP_VERSION
;   BUNDLE_DIR
;   OUTPUT_EXE
;   START_MENU_DIR
;   INSTALL_DIR
;   APP_LAUNCHER
;   APP_ICON

!ifndef APP_NAME
!define APP_NAME "Artemis"
!endif

!ifndef APP_VERSION
!define APP_VERSION "0.0.0"
!endif

!ifndef START_MENU_DIR
!define START_MENU_DIR "Artemis"
!endif

!ifndef INSTALL_DIR
!define INSTALL_DIR "$PROGRAMFILES32\Artemis"
!endif

!ifndef APP_LAUNCHER
!define APP_LAUNCHER "bin\com.k0vcz.Artemis.exe"
!endif

!ifndef APP_ICON
!define APP_ICON ""
!endif

!ifndef BUNDLE_DIR
!error "BUNDLE_DIR must be provided (installer input directory)"
!endif

!ifndef OUTPUT_EXE
!error "OUTPUT_EXE must be provided (installer output path)"
!endif

Unicode true
Name "${APP_NAME}"
OutFile "${OUTPUT_EXE}"
InstallDir "${INSTALL_DIR}"
InstallDirRegKey HKLM "Software\${APP_NAME}" "InstallDir"
RequestExecutionLevel admin

VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"

!if "${APP_ICON}" != ""
Icon "${APP_ICON}"
UninstallIcon "${APP_ICON}"
!endif

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${BUNDLE_DIR}\*"

  CreateDirectory "$SMPROGRAMS\${START_MENU_DIR}"
  CreateShortcut "$SMPROGRAMS\${START_MENU_DIR}\${APP_NAME}.lnk" "$INSTDIR\${APP_LAUNCHER}"
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_LAUNCHER}"

  WriteRegStr HKLM "Software\${APP_NAME}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher" "K0VCZ"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${START_MENU_DIR}\${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${START_MENU_DIR}"

  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
  DeleteRegKey HKLM "Software\${APP_NAME}"
SectionEnd
