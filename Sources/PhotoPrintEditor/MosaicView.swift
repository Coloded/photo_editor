import SwiftUI
import UniformTypeIdentifiers

struct MosaicView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = MosaicModel()
    @State private var isImporterPresented = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.text("Мозаика для печати", "Print mosaic"))
                            .font(.title2.weight(.semibold))
                        Text(settings.text("Автоматическая сетка или свободная раскладка", "Automatic grid or free layout"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(settings.text("Добавить фото…", "Add photos…"), systemImage: "photo.on.rectangle.angled")
                    }
                }
                .padding(20)

                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    if model.items.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "square.grid.3x3.square")
                                .font(.system(size: 54, weight: .light))
                                .foregroundStyle(Color.accentColor)
                            Text(settings.text("Перетащите несколько фотографий", "Drop multiple photos"))
                                .font(.title3.weight(.semibold))
                            Text(settings.text(
                                "Перетащите, выберите или вставьте фотографии через ⌘V",
                                "Drop, choose, or paste photos with ⌘V"
                            ))
                                .foregroundStyle(.secondary)
                            Button(settings.text("Выбрать фотографии…", "Choose photos…")) { isImporterPresented = true }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                    } else {
                        MosaicCanvasView(model: model)
                            .padding(26)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(model.isDropTargeted ? Color.accentColor : .clear, lineWidth: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                HStack {
                    Image(systemName: model.items.isEmpty ? "info.circle" : "checkmark.circle.fill")
                        .foregroundStyle(model.items.isEmpty ? Color.secondary : Color.green)
                    Text(model.statusMessage).lineLimit(1)
                    Spacer()
                    Text(settings.text("\(model.items.count) фото", "\(model.items.count) photos"))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
            .frame(minWidth: 600)

            Divider()
            settingsPanel
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.loadImages(from: urls) }
        }
        .onDrop(of: DropImageLoader.acceptedTypes, isTargeted: $model.isDropTargeted) { providers in
            loadImages(from: providers, isPaste: false)
            return true
        }
        .onPasteCommand(of: DropImageLoader.acceptedTypes) { providers in
            loadImages(from: providers, isPaste: true)
        }
        .onChange(of: settings.language) { _ in model.refreshLanguage() }
    }

    private func loadImages(from providers: [NSItemProvider], isPaste: Bool) {
        for provider in providers {
            DropImageLoader.load(from: provider) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let payload):
                        if isPaste {
                            model.addPastedImage(
                                data: payload.data,
                                suggestedName: payload.suggestedName
                            )
                        } else {
                            model.addDroppedImage(
                                data: payload.data,
                                suggestedName: payload.suggestedName
                            )
                        }
                    case .failure(let error):
                        model.statusMessage = error.localizedDescription
                        NSSound.beep()
                    }
                }
            }
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(settings.text("Лист", "Sheet"), systemImage: "doc")
                    .font(.headline)

                Picker(settings.text("Формат", "Format"), selection: $model.paperPresetID) {
                    ForEach(PaperPreset.all) { paper in
                        Text(paper.displayName(settings.language)).tag(paper.id)
                    }
                }
                .onChange(of: model.paperPresetID) { _ in model.paperSettingsChanged() }

                Picker(settings.text("Ориентация", "Orientation"), selection: $model.isLandscape) {
                    Text(settings.text("Книжная", "Portrait")).tag(false)
                    Text(settings.text("Альбомная", "Landscape")).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: model.isLandscape) { _ in model.paperSettingsChanged() }

                Picker(settings.text("Размещение", "Layout"), selection: $model.layoutMode) {
                    ForEach(MosaicLayoutMode.allCases) { Text($0.displayName(settings.language)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.layoutMode) { mode in
                    if mode == .grid { model.arrangeGrid() }
                }

                if !model.items.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(settings.text("Фото на листе", "Photos on sheet"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 7) {
                                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        model.selectedItemID = item.id
                                    } label: {
                                        ZStack(alignment: .topLeading) {
                                            Image(nsImage: item.image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 52, height: 52)
                                                .clipped()
                                            Text("\(index + 1)")
                                                .font(.caption2.bold())
                                                .padding(3)
                                                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                                                .foregroundStyle(.white)
                                                .padding(3)
                                        }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 7)
                                                .stroke(
                                                    model.selectedItemID == item.id ? Color.accentColor : Color.clear,
                                                    lineWidth: 3
                                                )
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if model.layoutMode == .grid {
                    HStack {
                        compactSlider(settings.text("Поля", "Margins"), value: $model.marginMM, range: 0...30, suffix: settings.text("мм", "mm"))
                        compactSlider(settings.text("Интервал", "Gap"), value: $model.gapMM, range: 0...20, suffix: settings.text("мм", "mm"))
                    }
                    .onChange(of: model.marginMM) { _ in model.arrangeGrid() }
                    .onChange(of: model.gapMM) { _ in model.arrangeGrid() }

                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(settings.text("Прилипать к фото и краям листа", "Snap to photos and sheet edges"), isOn: $model.snapEnabled)
                        Text(settings.text(
                            "С галочкой края стыкуются без зазора, а увеличиваемое фото раздвигает соседние снимки. Без галочки разрешено наложение.",
                            "When enabled, edges join without gaps and a growing photo pushes neighboring images. Disable it to allow overlap."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    model.autoArrange()
                } label: {
                    Label(settings.text("Автоматически расставить", "Auto arrange"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.items.isEmpty)

                if let selectedName = model.selectedItemName, model.layoutMode == .free {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(settings.text("Выбранное фото", "Selected photo"), systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                        Text(selectedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack {
                            Button {
                                model.scaleSelected(by: 0.9)
                            } label: {
                                Label("−10%", systemImage: "minus.magnifyingglass")
                            }
                            Button {
                                model.scaleSelected(by: 1.1)
                            } label: {
                                Label("+10%", systemImage: "plus.magnifyingglass")
                            }
                        }
                        Text(settings.text(
                            "Также можно перетащить фото или потянуть за синюю точку в его углу.",
                            "You can also drag the photo or pull the blue handle in its corner."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(settings.text(
                        "Нажмите на фотографию, чтобы выделить её синей рамкой.",
                        "Click a photo to select it with a blue border."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(settings.text("Удалить выбранное", "Remove selected")) { model.removeSelected() }
                        .disabled(model.selectedItemID == nil)
                    Button(settings.text("Очистить", "Clear")) { model.removeAll() }
                        .disabled(model.items.isEmpty)
                }

                Divider()
                Label(settings.text("Экспорт листа", "Export sheet"), systemImage: "printer")
                    .font(.headline)

                Picker(settings.text("Формат", "Format"), selection: $model.exportFormat) {
                    ForEach(MosaicExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }

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
                }

                if model.exportFormat == .jpeg {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(settings.text("Качество JPG", "JPG quality"))
                            Spacer()
                            Text("\(Int(model.jpegQuality * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.jpegQuality, in: 0.5...1.0, step: 0.01)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.text("Итоговый лист", "Output sheet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.outputDescription)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
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
                    Label(settings.text("Сохранить лист как…", "Save sheet as…"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.items.isEmpty)
            }
            .padding(22)
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }

    private func compactSlider(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title): \(Int(value.wrappedValue)) \(suffix)")
                .font(.caption)
            Slider(value: value, in: range, step: 1)
        }
    }
}
