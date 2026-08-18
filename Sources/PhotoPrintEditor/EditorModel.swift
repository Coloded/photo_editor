import AppKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Metal
import UniformTypeIdentifiers

struct PrintPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let widthMM: Double
    let heightMM: Double
    let category: String

    func displayName(_ language: AppLanguage) -> String {
        guard language == .en else { return name }
        return switch id {
        case "custom": "Custom"
        case "doc_30x40": "Document 30 × 40 mm"
        case "doc_35x45": "Document 35 × 45 mm"
        case "doc_40x50": "Document 40 × 50 mm"
        case "photo_9x13": "Photo 9 × 13 cm"
        case "photo_10x15": "Photo 10 × 15 cm"
        case "photo_13x18": "Photo 13 × 18 cm"
        case "photo_15x21": "Photo 15 × 21 cm"
        case "photo_20x30": "Photo 20 × 30 cm"
        case "paper_a6": "A6 sheet — 105 × 148 mm"
        case "paper_a5": "A5 sheet — 148 × 210 mm"
        case "paper_a4": "A4 sheet — 210 × 297 mm"
        case "paper_a3": "A3 sheet — 297 × 420 mm"
        case "paper_a2": "A2 sheet — 420 × 594 mm"
        default: name
        }
    }

    static let all: [PrintPreset] = [
        .init(id: "custom", name: "Произвольный", widthMM: 0, heightMM: 0, category: "Размер"),
        .init(id: "doc_30x40", name: "Документ 30 × 40 мм", widthMM: 30, heightMM: 40, category: "Документы"),
        .init(id: "doc_35x45", name: "Документ 35 × 45 мм", widthMM: 35, heightMM: 45, category: "Документы"),
        .init(id: "doc_40x50", name: "Документ 40 × 50 мм", widthMM: 40, heightMM: 50, category: "Документы"),
        .init(id: "photo_9x13", name: "Фото 9 × 13 см", widthMM: 90, heightMM: 130, category: "Фотографии"),
        .init(id: "photo_10x15", name: "Фото 10 × 15 см", widthMM: 100, heightMM: 150, category: "Фотографии"),
        .init(id: "photo_13x18", name: "Фото 13 × 18 см", widthMM: 130, heightMM: 180, category: "Фотографии"),
        .init(id: "photo_15x21", name: "Фото 15 × 21 см", widthMM: 150, heightMM: 210, category: "Фотографии"),
        .init(id: "photo_20x30", name: "Фото 20 × 30 см", widthMM: 200, heightMM: 300, category: "Фотографии"),
        .init(id: "paper_a6", name: "Лист A6 — 105 × 148 мм", widthMM: 105, heightMM: 148, category: "Листы ISO"),
        .init(id: "paper_a5", name: "Лист A5 — 148 × 210 мм", widthMM: 148, heightMM: 210, category: "Листы ISO"),
        .init(id: "paper_a4", name: "Лист A4 — 210 × 297 мм", widthMM: 210, heightMM: 297, category: "Листы ISO"),
        .init(id: "paper_a3", name: "Лист A3 — 297 × 420 мм", widthMM: 297, heightMM: 420, category: "Листы ISO"),
        .init(id: "paper_a2", name: "Лист A2 — 420 × 594 мм", widthMM: 420, heightMM: 594, category: "Листы ISO")
    ]
}

enum PrintUnit: String, CaseIterable, Identifiable {
    case millimeters = "мм"
    case centimeters = "см"

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .millimeters: language == .ru ? "мм" : "mm"
        case .centimeters: language == .ru ? "см" : "cm"
        }
    }

    func inches(from value: Double) -> Double {
        switch self {
        case .millimeters: value / 25.4
        case .centimeters: value / 2.54
        }
    }

    func converted(_ value: Double, from oldUnit: PrintUnit) -> Double {
        guard oldUnit != self else { return value }
        return switch (oldUnit, self) {
        case (.millimeters, .centimeters): value / 10
        case (.centimeters, .millimeters): value * 10
        default: value
        }
    }
}

enum ResizeMode: String, CaseIterable, Identifiable {
    case fill = "Заполнить с обрезкой"
    case fit = "Вписать с полями"

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .fill: language == .ru ? "Заполнить с обрезкой" : "Fill and crop"
        case .fit: language == .ru ? "Вписать с полями" : "Fit with margins"
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPG"
    case png = "PNG"
    case heic = "HEIC"
    case tiff = "TIFF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }

    var contentType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        }
    }
}

struct BlurMark {
    let normalizedPoint: CGPoint
    let level: Int
}

@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var sourceURL: URL?
    @Published private(set) var originalImage: NSImage?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var sourcePixelSize: CGSize = .zero
    @Published var width: Double = 40
    @Published var height: Double = 50
    @Published var unit: PrintUnit = .millimeters
    @Published var selectedPresetID = "doc_40x50"
    @Published var dpi: Int = 300
    @Published var resizeMode: ResizeMode = .fill
    @Published var exportFormat: ExportFormat = .jpeg
    @Published var jpegQuality: Double = 0.94
    @Published var brushLevel: Int = 4
    @Published var activeTool: EditorTool = .blur
    @Published var lineWidth: Int = 4
    @Published var drawingColor: NSColor = .systemRed
    @Published private(set) var annotations: [PhotoAnnotation] = []
    @Published var statusMessage = localized(
        "Перетащите фото сюда или нажмите «Обзор»",
        "Drop a photo here or click Browse"
    )
    @Published var isDropTargeted = false

    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(
                mtlDevice: device,
                options: [.cacheIntermediates: true, .name: "ФотоРазмер Metal"]
            )
        }
        return CIContext(options: [.cacheIntermediates: true])
    }()
    private var originalCIImage: CIImage?
    private var workingCIImage: CIImage?
    private var blurMarks: [BlurMark] = []

    var outputPixelSize: CGSize {
        let w = max(1, Int((unit.inches(from: width) * Double(dpi)).rounded()))
        let h = max(1, Int((unit.inches(from: height) * Double(dpi)).rounded()))
        return CGSize(width: w, height: h)
    }

    var sourceDescription: String {
        guard sourcePixelSize != .zero else { return "Фото не выбрано" }
        return "\(Int(sourcePixelSize.width)) × \(Int(sourcePixelSize.height)) px"
    }

    var outputDescription: String {
        let size = outputPixelSize
        return "\(Int(size.width)) × \(Int(size.height)) px · \(dpi) DPI"
    }

    var estimatedFileSizeText: String {
        let pixels = Double(outputPixelSize.width * outputPixelSize.height)
        let bytesPerPixel: Double
        switch exportFormat {
        case .jpeg: bytesPerPixel = 0.10 + jpegQuality * 0.82
        case .heic: bytesPerPixel = 0.06 + jpegQuality * 0.46
        case .png: bytesPerPixel = 2.2
        case .tiff: bytesPerPixel = 3.05
        }
        let estimatedBytes = max(1_024, pixels * bytesPerPixel)
        return ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }

    func applyPreset(_ id: String) {
        selectedPresetID = id
        guard let preset = PrintPreset.all.first(where: { $0.id == id }), id != "custom" else { return }
        unit = .millimeters
        width = preset.widthMM
        height = preset.heightMM
    }

    func markSizeAsCustom() {
        selectedPresetID = "custom"
    }

    func swapDimensions() {
        (width, height) = (height, width)
    }

    func refreshLanguage() {
        if let sourceURL {
            statusMessage = localized("Загружено", "Loaded") + ": \(sourceURL.lastPathComponent)"
        } else {
            statusMessage = localized(
                "Перетащите фото сюда или нажмите «Обзор»",
                "Drop a photo here or click Browse"
            )
        }
    }

    func setUnit(_ newUnit: PrintUnit) {
        let oldUnit = unit
        width = newUnit.converted(width, from: oldUnit)
        height = newUnit.converted(height, from: oldUnit)
        unit = newUnit
    }

    func loadImage(from url: URL) {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            statusMessage = localized("Не удалось открыть изображение", "Could not open the image")
            NSSound.beep()
            return
        }
        installImage(from: source, displayURL: url)
    }

    func loadImage(data: Data, suggestedName: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            statusMessage = localized(
                "Не удалось прочитать изображение из приложения «Фото»",
                "Could not read the image from Photos"
            )
            NSSound.beep()
            return
        }
        installImage(from: source, displayURL: URL(fileURLWithPath: suggestedName))
    }

    func loadPastedImage(data: Data, suggestedName: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            statusMessage = localized(
                "Буфер обмена не содержит поддерживаемого изображения",
                "The clipboard does not contain a supported image"
            )
            NSSound.beep()
            return
        }
        installImage(from: source, displayURL: URL(fileURLWithPath: suggestedName))
        statusMessage = localized("Вставлено из буфера обмена", "Pasted from clipboard")
    }

    private func installImage(from source: CGImageSource, displayURL: URL) {
        guard let cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            statusMessage = localized("Не удалось открыть изображение", "Could not open the image")
            NSSound.beep()
            return
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        var ciImage = CIImage(cgImage: cgImage).oriented(forExifOrientation: orientation)
        ciImage = ciImage.transformed(
            by: CGAffineTransform(translationX: -ciImage.extent.minX, y: -ciImage.extent.minY)
        )
        guard let orientedCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            statusMessage = localized("Не удалось подготовить изображение", "Could not prepare the image")
            return
        }

        sourceURL = displayURL
        sourcePixelSize = CGSize(width: orientedCGImage.width, height: orientedCGImage.height)
        originalCIImage = ciImage
        workingCIImage = ciImage
        blurMarks.removeAll()
        annotations.removeAll()

        let nsImage = NSImage(
            cgImage: orientedCGImage,
            size: NSSize(width: orientedCGImage.width, height: orientedCGImage.height)
        )
        originalImage = nsImage
        previewImage = nsImage
        statusMessage = localized("Загружено", "Loaded") + ": \(displayURL.lastPathComponent)"
    }

    func applyBlur(at normalizedPoint: CGPoint) {
        guard workingCIImage != nil else { return }
        let mark = BlurMark(
            normalizedPoint: CGPoint(
                x: min(max(normalizedPoint.x, 0), 1),
                y: min(max(normalizedPoint.y, 0), 1)
            ),
            level: brushLevel
        )
        blurMarks.append(mark)
        if let current = workingCIImage {
            let updated = applyingBlur(mark, to: current)
            workingCIImage = updated
            updatePreview(from: updated)
        }
    }

    func undoBlur() {
        guard !blurMarks.isEmpty else { return }
        blurMarks.removeLast()
        renderBlurMarks()
    }

    func resetBlur() {
        blurMarks.removeAll()
        renderBlurMarks()
    }

    func addAnnotation(tool: EditorTool, start: CGPoint, end: CGPoint) {
        guard tool != .blur else { return }
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 0.004 else { return }
        annotations.append(PhotoAnnotation(
            tool: tool,
            start: start,
            end: end,
            color: AnnotationColor(drawingColor),
            relativeLineWidth: CGFloat(lineWidth) / 500
        ))
    }

    func undoAnnotation() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    func resetAnnotations() {
        annotations.removeAll()
    }

    func save() {
        guard let image = workingCIImage else {
            statusMessage = localized("Сначала выберите фотографию", "Select a photo first")
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.title = localized("Сохранить фотографию", "Save photo")
        panel.prompt = localized("Сохранить", "Save")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [exportFormat.contentType]
        let stem = sourceURL?.deletingPathExtension().lastPathComponent ?? "photo"
        panel.nameFieldStringValue = "\(stem)_\(Int(width))x\(Int(height))\(unit.rawValue).\(exportFormat.fileExtension)"

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let url = selectedURL.deletingPathExtension().appendingPathExtension(exportFormat.fileExtension)

        do {
            let target = outputPixelSize
            guard target.width <= 30_000, target.height <= 30_000,
                  target.width * target.height <= 200_000_000 else {
                throw ExportError.invalidSize
            }
            let outputImage = try resizedImage(from: image, targetSize: target)
            try write(outputImage, to: url)
            statusMessage = localized("Сохранено", "Saved") + ": \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            statusMessage = localized("Ошибка сохранения", "Save error") + ": \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func renderBlurMarks() {
        guard let original = originalCIImage else { return }
        var image = original
        for mark in blurMarks {
            image = applyingBlur(mark, to: image)
        }
        workingCIImage = image
        updatePreview(from: image)
    }

    private func updatePreview(from image: CIImage) {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        previewImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private func applyingBlur(_ mark: BlurMark, to image: CIImage) -> CIImage {
        let extent = image.extent
        let center = CGPoint(
            x: extent.minX + mark.normalizedPoint.x * extent.width,
            y: extent.minY + (1 - mark.normalizedPoint.y) * extent.height
        )
        let minSide = min(extent.width, extent.height)
        let radius = minSide * (0.012 + Double(mark.level) * 0.009)
        let blurRadius = 1.5 + Double(mark.level) * 1.8

        let blurred = image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurRadius)
            .cropped(to: extent)

        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(radius * 0.45)
        gradient.radius1 = Float(radius)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = image
        blend.maskImage = gradient.outputImage?.cropped(to: extent)
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    private func resizedImage(from image: CIImage, targetSize: CGSize) throws -> CGImage {
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)
        let source = image.extent
        let scaleX = CGFloat(targetWidth) / source.width
        let scaleY = CGFloat(targetHeight) / source.height
        let scale = resizeMode == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let x = (CGFloat(targetWidth) - scaledWidth) / 2
        let y = (CGFloat(targetHeight) - scaledHeight) / 2

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ExportError.renderFailed
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.interpolationQuality = .high

        guard let sourceCGImage = ciContext.createCGImage(image, from: source) else {
            throw ExportError.renderFailed
        }
        context.draw(sourceCGImage, in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
        let imageRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        for annotation in annotations {
            AnnotationRenderer.draw(annotation, in: imageRect, context: context)
        }
        context.restoreGState()

        guard let result = context.makeImage() else { throw ExportError.renderFailed }
        return result
    }

    private func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            exportFormat.contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.unsupportedFormat
        }

        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        if exportFormat == .jpeg || exportFormat == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.writeFailed
        }
    }
}

enum ExportError: LocalizedError {
    case invalidSize
    case renderFailed
    case unsupportedFormat
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidSize: localized("Слишком большой размер изображения", "Image size is too large")
        case .renderFailed: localized("Не удалось подготовить изображение", "Could not render the image")
        case .unsupportedFormat: localized("Формат не поддерживается системой", "The format is not supported")
        case .writeFailed: localized("Не удалось записать файл", "Could not write the file")
        }
    }
}
