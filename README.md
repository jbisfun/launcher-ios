# launcher-ios

The Fossify iOS ports bundled into one app ("Fossify"): a home screen of app tiles; each app opens full screen with a home button on its main screen to return. vCards shared to the launcher open in Contacts' import dialog.

    idl build -c release     # -> build/release/FossifyLauncher.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyLauncher

Each app still builds on its own. Its repo splits into a static `<App>Kit` module (`Sources/`, public entry view `CalculatorRoot` / `ContactsRoot`) and a one-file app target (`App/main.swift`). The launcher links the kits and [commons-ios](https://github.com/jbisfun/commons-ios) from the sibling checkouts in `fossify-ios/` (calculator-ios, contacts-ios, commons-ios). An app hosted by the launcher gets `\.closeApp` in its environment and shows `CloseAppButton`.

Adding an app: give it the Kit/App split, add its Kit target to `idlproj.yml`, merge its Info.plist keys into the launcher's `info:`, add a case to `BundledApp` plus a 180 px icon imageset.

GPL-3.0.
