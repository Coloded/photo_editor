import SwiftUI

@main
struct PhotoPrintEditorApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var updateController = UpdateController()

    var body: some Scene {
        WindowGroup("Photo_Editor") {
            ContentView()
                .environmentObject(settings)
                .environment(\.locale, settings.language.locale)
                .frame(minWidth: 920, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(settings.text("О программе Photo_Editor", "About Photo_Editor")) {
                    AboutPanel.show(settings: settings, updateController: updateController)
                }
                Button(settings.text("Проверить обновления…", "Check for Updates…")) {
                    updateController.checkForUpdates()
                }
            }
            CommandGroup(replacing: .newItem) { }
            CommandMenu(settings.text("Язык", "Language")) {
                Button(settings.language == .ru ? "✓ Русский" : "Русский") {
                    settings.language = .ru
                }
                Button(settings.language == .en ? "✓ English" : "English") {
                    settings.language = .en
                }
            }
        }
    }
}
