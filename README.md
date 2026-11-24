# launcher-ios

The Fossify iOS ports bundled into one app ("Fossify"): a home screen of app tiles; each app opens full screen with a home button on its main screen to return. vCards shared to the launcher open in Contacts' import dialog.

    idl build -c release     # -> build/release/FossifyLauncher.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyLauncher

Bundled: Calculator, Calendar, Camera, Clock, Contacts, Documents, File Manager, Gallery, Keyboard (in-app only; the system keyboard extension ships with keyboard-ios), Messages, Music Player, Notes, Paint, Phone, Thank You, Voice Recorder. Files shared to the launcher are routed by type (`BundledApp.handling`): vCards to Contacts, .ics to Calendar, text to Notes, documents to Documents, audio to Music Player, images to Paint, the rest to File Manager. Notifications go through commons' `NotificationHub` so Clock and Calendar don't replace each other's delegate.

Each app still builds on its own. Its repo splits into a static `<App>Kit` module (`Sources/`, public entry view `CalculatorRoot` / `ContactsRoot`) and a one-file app target (`App/main.swift`). The launcher links the kits and [commons-ios](https://github.com/jbisfun/commons-ios) from the sibling checkouts in `fossify-ios/` (calculator-ios, contacts-ios, commons-ios). An app hosted by the launcher gets `\.closeApp` in its environment and shows `CloseAppButton`.

Adding an app: give it the Kit/App split, add its Kit target to `idlproj.yml`, merge its Info.plist keys into the launcher's `info:`, add a case to `BundledApp` (and its file types to `handling`) plus its 180 px icon as `Resources/AppIcons/<name>.png`. Resources of a Kit (e.g. Calendar's `Holidays.bundle`, Camera's `CameraSounds.bundle`) must be copied into `Resources/`, since idl resources can't point outside the target dir.

GPL-3.0.
