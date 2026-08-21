import AppKit
import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
}

@MainActor
final class AppSettings: ObservableObject {
    nonisolated static let languageKey = "appLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.languageKey),
           let language = AppLanguage(rawValue: saved) {
            self.language = language
        } else {
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            self.language = preferred.hasPrefix("ru") ? .ru : .en
        }
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    func text(_ russian: String, _ english: String) -> String {
        language == .ru ? russian : english
    }
}

func localized(_ russian: String, _ english: String) -> String {
    let raw = UserDefaults.standard.string(forKey: AppSettings.languageKey)
    let language = raw.flatMap(AppLanguage.init(rawValue:)) ??
        ((Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true) ? .ru : .en)
    return language == .ru ? russian : english
}

@MainActor
enum AboutPanel {
    private static var windowController: NSWindowController?

    static func show(settings: AppSettings, updateController: UpdateController) {
        let rootView = AboutView(settings: settings, updateController: updateController)

        if let windowController, let window = windowController.window {
            window.contentViewController = NSHostingController(rootView: rootView)
            window.title = settings.text("О программе Photo_Editor", "About Photo_Editor")
            windowController.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = settings.text("О программе Photo_Editor", "About Photo_Editor")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: rootView)
            window.center()
            let controller = NSWindowController(window: window)
            windowController = controller
            controller.showWindow(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct AboutView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateController: UpdateController

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)

            VStack(spacing: 4) {
                Text("Photo_Editor")
                    .font(.largeTitle.weight(.semibold))
                Text(settings.text("Версия \(appVersion)", "Version \(appVersion)"))
                    .foregroundStyle(.secondary)
            }

            Text(settings.text(
                "Нативный фоторедактор для подготовки фотографий и фотомозаик к печати на компьютерах Mac с Apple Silicon.",
                "A native photo editor for preparing photos and print mosaics on Macs with Apple Silicon."
            ))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(settings.text("Обновления", "Updates"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        Spacer()
                        Text(settings.text("Стабильный канал", "Stable channel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(settings.text(
                        "Photo_Editor проверяет подписанные обновления на GitHub и может установить новую версию в папку Applications.",
                        "Photo_Editor checks signed updates on GitHub and can install a new version into Applications."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Toggle(
                        settings.text("Проверять обновления автоматически", "Automatically check for updates"),
                        isOn: $updateController.automaticallyChecksForUpdates
                    )

                    Button {
                        updateController.checkForUpdates()
                    } label: {
                        Label(
                            settings.text("Проверить обновления…", "Check for Updates…"),
                            systemImage: "arrow.down.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(8)
            }

            Text(settings.text(
                "SwiftUI · Metal · Core Image · Sparkle\nТолько Apple Silicon · macOS 13 и новее",
                "SwiftUI · Metal · Core Image · Sparkle\nApple Silicon only · macOS 13 or later"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Link(
                settings.text("Исходный код на GitHub", "Source code on GitHub"),
                destination: URL(string: "https://github.com/Coloded/photo_editor")!
            )

            Text("© 2026 Photo_Editor")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 520, height: 560)
    }
}
