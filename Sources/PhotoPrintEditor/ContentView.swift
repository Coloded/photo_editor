import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case editor = "Одно фото"
    case mosaic = "Мозаика"

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .editor: language == .ru ? "Одно фото" : "Single photo"
        case .mosaic: language == .ru ? "Мозаика" : "Mosaic"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var section: WorkspaceSection = .editor

    var body: some View {
        VStack(spacing: 0) {
            Picker(settings.text("Режим", "Mode"), selection: $section) {
                ForEach(WorkspaceSection.allCases) { item in
                    Text(item.displayName(settings.language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .padding(.vertical, 10)

            Divider()

            switch section {
            case .editor:
                SinglePhotoEditorView()
            case .mosaic:
                MosaicView()
            }
        }
    }
}

private struct SinglePhotoEditorView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = EditorModel()
    @State private var isImporterPresented = false

    var body: some View {
        HStack(spacing: 0) {
            editorArea
            Divider()
            settingsPanel
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.loadImage(from: url)
            }
        }
        .onDrop(of: DropImageLoader.acceptedTypes, isTargeted: $model.isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            loadImage(from: provider, isPaste: false)
            return true
        }
        .onPasteCommand(of: DropImageLoader.acceptedTypes) { providers in
            guard let provider = providers.first else { return }
            loadImage(from: provider, isPaste: true)
        }
        .onChange(of: settings.language) { _ in model.refreshLanguage() }
    }

    private func loadImage(from provider: NSItemProvider, isPaste: Bool) {
        DropImageLoader.load(from: provider) { result in
            Task { @MainActor in
                switch result {
                case .success(let payload):
                    if isPaste {
                        model.loadPastedImage(data: payload.data, suggestedName: payload.suggestedName)
                    } else {
                        model.loadImage(data: payload.data, suggestedName: payload.suggestedName)
                    }
                case .failure(let error):
                    model.statusMessage = error.localizedDescription
                    NSSound.beep()
                }
            }
        }
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Photo_Editor")
                        .font(.title2.weight(.semibold))
                    Text(settings.text("Размер для печати и редактирование", "Print sizing and editing"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isImporterPresented = true
                } label: {
                    Label(settings.text("Обзор…", "Browse…"), systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            .padding(20)

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(model.isDropTargeted ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                model.isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                style: StrokeStyle(lineWidth: model.isDropTargeted ? 2 : 1, dash: model.previewImage == nil ? [8] : [])
                            )
                    }

                if model.previewImage != nil {
                    BlurCanvasView(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(14)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(Color.accentColor)
                        Text(settings.text("Перетащите фотографию", "Drop a photo"))
                            .font(.title3.weight(.semibold))
                        Text(settings.text(
                            "или выберите файл либо вставьте изображение через ⌘V",
                            "or choose a file or paste an image with ⌘V"
                        ))
                            .foregroundStyle(.secondary)
                        Button(settings.text("Выбрать фото…", "Choose photo…")) { isImporterPresented = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            HStack {
                Image(systemName: model.previewImage == nil ? "info.circle" : "checkmark.circle.fill")
                    .foregroundStyle(model.previewImage == nil ? Color.secondary : Color.green)
                Text(model.statusMessage)
                    .lineLimit(1)
                Spacer()
                Text(model.sourceDescription)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 600)
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                panelHeader(settings.text("Размер печати", "Print size"), systemImage: "ruler")

                Picker(settings.text("Стандартный размер", "Standard size"), selection: Binding(
                    get: { model.selectedPresetID },
                    set: { model.applyPreset($0) }
                )) {
                    ForEach(PrintPreset.all) { preset in
                        Text(preset.displayName(settings.language)).tag(preset.id)
                    }
                }

                Picker(settings.text("Единицы", "Units"), selection: Binding(
                    get: { model.unit },
                    set: { model.setUnit($0) }
                )) {
                    ForEach(PrintUnit.allCases) { Text($0.displayName(settings.language)).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    numberField(settings.text("Ширина", "Width"), value: $model.width)
                    numberField(settings.text("Высота", "Height"), value: $model.height)
                }

                Button {
                    model.swapDimensions()
                } label: {
                    Label(settings.text("Поменять местами", "Swap dimensions"), systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(settings.text("Разрешение", "Resolution"))
                        Spacer()
                        Text("\(model.dpi) DPI").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(model.dpi) },
                        set: { model.dpi = Int($0.rounded()) }
                    ), in: 72...600, step: 1)
                    HStack {
                        Button("150") { model.dpi = 150 }
                        Button("300") { model.dpi = 300 }
                        Button("600") { model.dpi = 600 }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                Picker(settings.text("Кадрирование", "Cropping"), selection: $model.resizeMode) {
                    ForEach(ResizeMode.allCases) { Text($0.displayName(settings.language)).tag($0) }
                }

                Divider()
                panelHeader(settings.text("Инструменты", "Tools"), systemImage: "pencil.and.outline")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach(EditorTool.allCases) { tool in
                        Button {
                            model.activeTool = tool
                        } label: {
                            Label(tool.displayName(settings.language), systemImage: tool.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(model.activeTool == tool ? Color.accentColor : Color.secondary)
                    }
                }

                if model.activeTool == .blur {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(settings.text("Размер кисти", "Brush size"))
                            Spacer()
                            Text(settings.text("\(model.brushLevel) из 10", "\(model.brushLevel) of 10"))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(model.brushLevel) },
                            set: { model.brushLevel = Int($0.rounded()) }
                        ), in: 1...10, step: 1)
                        Text(settings.text(
                            "Проведите мышью по фотографии, чтобы размыть выбранное место.",
                            "Drag over the photo to blur an area."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(settings.text("Отменить размытие", "Undo blur")) { model.undoBlur() }
                            .disabled(model.previewImage == nil)
                        Button(settings.text("Сбросить", "Reset")) { model.resetBlur() }
                            .disabled(model.previewImage == nil)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(settings.text("Толщина линии", "Line width"))
                            Spacer()
                            Text(settings.text("\(model.lineWidth) из 10", "\(model.lineWidth) of 10"))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(model.lineWidth) },
                            set: { model.lineWidth = Int($0.rounded()) }
                        ), in: 1...10, step: 1)
                        ColorPicker(
                            settings.text("Цвет линии", "Line color"),
                            selection: Binding(
                                get: { Color(nsColor: model.drawingColor) },
                                set: { model.drawingColor = NSColor($0) }
                            ),
                            supportsOpacity: true
                        )
                        Text(settings.text(
                            "Нажмите на фотографию и протяните мышь до конечной точки фигуры.",
                            "Click the photo and drag to the shape's end point."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(settings.text("Отменить фигуру", "Undo shape")) { model.undoAnnotation() }
                        Button(settings.text("Очистить фигуры", "Clear shapes")) { model.resetAnnotations() }
                    }
                }

                Divider()
                panelHeader(settings.text("Экспорт", "Export"), systemImage: "square.and.arrow.down")

                Picker(settings.text("Формат", "Format"), selection: $model.exportFormat) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }

                if model.exportFormat == .jpeg || model.exportFormat == .heic {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(settings.text("Качество", "Quality"))
                            Spacer()
                            Text("\(Int(model.jpegQuality * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.jpegQuality, in: 0.5...1.0, step: 0.01)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.text("Итоговый файл", "Output file"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.outputDescription)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                    Text(settings.text(
                        "Ожидаемый размер: ≈ \(model.estimatedFileSizeText)",
                        "Estimated size: ≈ \(model.estimatedFileSizeText)"
                    ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    model.save()
                } label: {
                    Label(settings.text("Сохранить как…", "Save as…"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.previewImage == nil || model.width <= 0 || model.height <= 0)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(22)
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    private func panelHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                Text(model.unit.displayName(settings.language)).foregroundStyle(.secondary)
            }
        }
    }
}
