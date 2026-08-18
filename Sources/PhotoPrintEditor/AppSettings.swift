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
    static func show(language: AppLanguage) {
        let russian = """
        Фоторедактор для компьютеров Mac с процессорами Apple Silicon — M1, M2, M3, M4 и новее. Требуется macOS 13 Ventura или более новая версия.

        Подготовка фотографий и фотомозаик к печати: размеры в миллиметрах и сантиметрах, DPI, листы A0–A6, локальное размытие, линии, стрелки и геометрические фигуры.

        Используются нативные технологии macOS: SwiftUI, Metal, Core Image, ImageIO, Core Graphics и PDF. Приложение оптимизировано исключительно для Apple Silicon и работает без Rosetta.

        © 2026 Photo_Editor
        """
        let english = """
        A photo editor for Macs with Apple Silicon — M1, M2, M3, M4 and newer. Requires macOS 13 Ventura or later.

        Prepare photos and photo mosaics for printing: millimeter and centimeter sizes, DPI, A0–A6 sheets, local blur, lines, arrows, and geometric shapes.

        Built with native macOS technologies: SwiftUI, Metal, Core Image, ImageIO, Core Graphics, and PDF. Optimized exclusively for Apple Silicon and runs without Rosetta.

        © 2026 Photo_Editor
        """
        let credits = NSAttributedString(
            string: language == .ru ? russian : english,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Photo_Editor",
            .applicationVersion: "1.2",
            .version: language == .ru ? "Версия 1.2" : "Version 1.2",
            .credits: credits
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
