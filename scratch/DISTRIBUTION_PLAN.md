# Kjol Distribution & In-App Updater Architecture Plan

**Document Status:** Active / Specification
**Repository:** `Wiltermoodj/kjol`
**Target OS:** macOS 13.0+ (Apple Silicon optimized)

## 1. Executive Summary

This document specifies how Kjol is packaged and distributed to end-users as a single-file installer (`Kjol.pkg`), and how Kjol does in-app updates directly from GitHub Releases (`Wiltermoodj/kjol`).

The distribution design is tailored for **non-technical users**:
1. **Single-File Installation:** Users download a single `Kjol.pkg` installer package. Double-clicking it presents a standard macOS installer UI that prompts for administrator credentials once, installs `Kjol.app` to `/Applications`, configures and bootstraps the `com.lappier.kjol.helper` privileged LaunchDaemon, and immediately starts `Kjol.app` in the menu bar without requiring a reboot or terminal commands.
2. **Gatekeeper Guidance:** Since the app uses ad-hoc signing (`-s -`), macOS Gatekeeper will show an "Unidentified Developer" dialog on initial open. Simple step-by-step guidance (Right-Click -> Open or System Settings > Privacy & Security) is provided for non-technical users.
3. **In-App Updater:** Kjol automatically checks for updates silently when the menu bar popover opens, as well as providing a manual "Check for Updates" button in the UI footer. When a release on `Wiltermoodj/kjol` has a higher version tag, Kjol displays an update notification with an **"Update Now"** button. Clicking this downloads `Kjol.pkg` in the background and opens it with macOS Installer so the user can upgrade in one click.

## 2. Single-File Installer Package (`Kjol.pkg`) Architecture

### 2.1 Package Payload & Directory Layout

`build-kjol.sh` constructs a flat macOS installer package containing:
- `/Applications/Kjol.app` — The native SwiftUI/AppKit menu bar executable.
- `/Library/PrivilegedHelperTools/com.lappier.kjol.helper` — Root privileged LaunchDaemon executable.
- `/Library/LaunchDaemons/com.lappier.kjol.helper.plist` — Launchd configuration plist.

### 2.2 Post-Install Script Behavior

The `postinstall` script runs with root privileges at the end of package installation:
1. Fixes owner permissions (`root:wheel`) and access modes (`755` for helper binary, `644` for launchd plist, `700` for state directory `/var/db/kjol`).
2. Registers and bootstraps the LaunchDaemon (`launchctl bootstrap system /Library/LaunchDaemons/com.lappier.kjol.helper.plist`).
3. Detects the currently active console user (`CONSOLE_USER=$(stat -f "%Su" /dev/console)`).
4. Restarts `Kjol.app` in the active user's GUI session using `sudo -u "$CONSOLE_USER" open -a "/Applications/Kjol.app"`.

## 3. In-App Updater Architecture

### 3.1 GitHub Releases API Specification

- **Endpoint:** `https://api.github.com/repos/Wiltermoodj/kjol/releases/latest`
- **User-Agent:** `Kjol-Updater/1.0`
- **Response Handling:**
  - Parse `tag_name` (for example, `v1.0.1` or `1.0.1`).
  - Compare using Semantic Versioning against `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`.
  - Scan `assets` array for an item with `name` ending in `.pkg` (or matching `Kjol.pkg`), extracting `browser_download_url`.

### 3.2 `UpdateCheckerService` (Swift Service)

Location: `Kjol/UpdateCheckerService.swift`

Responsibilities:
- Asynchronously query GitHub Releases API using `URLSession`.
- Compare version strings (stripping leading `v` prefixes).
- Provide async methods:
  - `checkForUpdates() async throws -> UpdateInfo?`
  - `downloadInstaller(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL`

```swift
struct UpdateInfo {
    let version: String
    let releaseNotes: String
    let pkgDownloadURL: URL
}
```

### 3.3 `UpdateViewModel` & SwiftUI UI Integration

Location: `Kjol/ViewModels.swift` (or dedicated `UpdateViewModel.swift`)

State Management:
- `@Published var updateState: UpdateState = .idle`
  - `.idle`
  - `.checking`
  - `.available(UpdateInfo)`
  - `.upToDate`
  - `.downloading(progress: Double)`
  - `.readyToInstall(pkgLocalURL: URL)`
  - `.error(String)`

UI Integration in `FooterView` / Popover:
1. **Silent Check on Popover Open:** Triggered when popover is shown (debounced so it checks at most once per hour).
2. **Manual Check Button:** Placed in the `FooterView` near version string.
3. **Update Banner:** When `.available(let info)` is active, a subtle card appears above the footer:
   - Text: "Update Available: v\(info.version)"
   - Button: "Update Now"
4. **Installation Execution:**
   - Clicking "Update Now" streams the `.pkg` download into `FileManager.default.temporaryDirectory`.
   - Upon download completion, executes `NSWorkspace.shared.open(pkgLocalURL)` which triggers macOS Installer GUI.

## 4. Gatekeeper & First-Run User Guide

Because the app is distributed through single file without Apple Developer ID signing certificates:
1. **First Download Gatekeeper Alert:** macOS will show: *"Kjol.pkg cannot be opened because it is from an unidentified developer."*
2. **User Instructions (Included in Release Notes & README):**
   - **Method A (Quickest):** Right-click (or Control-click) `Kjol.pkg` -> Select **Open** -> Click **Open** in the prompt.
   - **Method B (System Settings):** Open **System Settings** -> **Privacy & Security** -> Scroll to Security -> Click **Open Anyway** next to `Kjol.pkg`.

## 5. Summary of Deliverables

1. `build-kjol.sh` generates a single, standalone `Kjol.pkg` in the project root.
2. `Kjol.app` contains built-in background update checking and one-click update downloading from `Wiltermoodj/kjol`.
3. Installation automatically launches Kjol in the status bar with zero terminal commands required.
