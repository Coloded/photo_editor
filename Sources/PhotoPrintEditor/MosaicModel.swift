import AppKit
import Combine
import CoreImage
import ImageIO
import Metal
import UniformTypeIdentifiers

struct PaperPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let widthMM: CGFloat
    let heightMM: CGFloat

    func displayName(_ language: AppLanguage) -> String {
        guard language == .en else { return name }
        return name.replacingOccurrences(of: "мм", with: "mm")
    }

    static let all: [PaperPreset] = [
        .init(id: "a6", name: "A6 — 105 × 148 мм", widthMM: 105, heightMM: 148),
        .init(id: "a5", name: "A5 — 148 × 210 мм", widthMM: 148, heightMM: 210),
        .init(id: "a4", name: "A4 — 210 × 297 мм", widthMM: 210, heightMM: 297),
        .init(id: "a3", name: "A3 — 297 × 420 мм", widthMM: 297, heightMM: 420),
        .init(id: "a2", name: "A2 — 420 × 594 мм", widthMM: 420, heightMM: 594),
        .init(id: "a1", name: "A1 — 594 × 841 мм", widthMM: 594, heightMM: 841),
        .init(id: "a0", name: "A0 — 841 × 1189 мм", widthMM: 841, heightMM: 1189)
    ]
}

enum MosaicLayoutMode: String, CaseIterable, Identifiable {
    case grid = "Ровная сетка"
    case free = "Свободно"

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .grid: language == .ru ? "Ровная сетка" : "Even grid"
        case .free: language == .ru ? "Свободно" : "Free"
        }
    }
}

enum MosaicExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case jpeg = "JPG"
    case png = "PNG"

    var id: String { rawValue }

    var fileExtension: String { rawValue.lowercased() }

    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .jpeg: .jpeg
        case .png: .png
        }
    }
}

struct MosaicItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let image: NSImage
    let cgImage: CGImage
    var frameMM: CGRect
}

@MainActor
final class MosaicModel: ObservableObject {
    @Published var items: [MosaicItem] = []
    @Published var selectedItemID: UUID?
    @Published var paperPresetID = "a4"
    @Published var isLandscape = false
    @Published var layoutMode: MosaicLayoutMode = .grid
    @Published var snapEnabled = true
    @Published var dpi = 300
    @Published var marginMM: CGFloat = 10
    @Published var gapMM: CGFloat = 4
    @Published var exportFormat: MosaicExportFormat = .pdf
    @Published var jpegQuality = 0.92
    @Published var statusMessage = localized(
        "Перетащите несколько фотографий на лист",
        "Drop multiple photos onto the sheet"
    )
    @Published var isDropTargeted = false

    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: true, .name: "Мозаика Metal"])
        }
        return CIContext(options: [.cacheIntermediates: true])
    }()

    var selectedPaper: PaperPreset {
        PaperPreset.all.first(where: { $0.id == paperPresetID }) ?? PaperPreset.all[2]
    }

    var paperSizeMM: CGSize {
        let paper = selectedPaper
        return isLandscape
            ? CGSize(width: paper.heightMM, height: paper.widthMM)
            : CGSize(width: paper.widthMM, height: paper.heightMM)
    }

    var outputPixelSize: CGSize {
        CGSize(
            width: max(1, (paperSizeMM.width / 25.4 * CGFloat(dpi)).rounded()),
            height: max(1, (paperSizeMM.height / 25.4 * CGFloat(dpi)).rounded())
        )
    }

    var outputDescription: String {
        "\(Int(outputPixelSize.width)) × \(Int(outputPixelSize.height)) px · \(dpi) DPI"
    }

    var selectedItemName: String? {
        guard let selectedItemID,
              let item = items.first(where: { $0.id == selectedItemID }) else { return nil }
        return item.sourceURL.lastPathComponent
    }

    var estimatedFileSizeText: String {
        let pixels = Double(outputPixelSize.width * outputPixelSize.height)
        let bytesPerPixel: Double
        switch exportFormat {
        case .pdf: bytesPerPixel = 0.7
        case .jpeg: bytesPerPixel = 0.10 + jpegQuality * 0.82
        case .png: bytesPerPixel = 2.1
        }
        return ByteCountFormatter.string(
            fromByteCount: Int64(max(1_024, pixels * bytesPerPixel)),
            countStyle: .file
        )
    }

    func refreshLanguage() {
        statusMessage = items.isEmpty
            ? localized("Перетащите несколько фотографий на лист", "Drop multiple photos onto the sheet")
            : localized("Фотографий на листе", "Photos on sheet") + ": \(items.count)"
    }

    func loadImages(from urls: [URL]) {
        var added = 0
        for url in urls where url.isFileURL {
            guard let loaded = loadOrientedImage(from: url) else { continue }
            items.append(MosaicItem(
                sourceURL: url,
                image: loaded.nsImage,
                cgImage: loaded.cgImage,
                frameMM: CGRect(x: marginMM, y: marginMM, width: 40, height: 40)
            ))
            added += 1
        }
        if added > 0 {
            arrangeGrid()
            statusMessage = localized("Добавлено фотографий", "Photos added") +
                ": \(added). " + localized("Всего", "Total") + ": \(items.count)"
        } else {
            statusMessage = localized("Не удалось открыть выбранные изображения", "Could not open selected images")
            NSSound.beep()
        }
    }

    func addDroppedImage(data: Data, suggestedName: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let loaded = loadOrientedImage(
                from: source,
                displayURL: URL(fileURLWithPath: suggestedName)
              ) else {
            statusMessage = localized(
                "Не удалось получить изображение из приложения «Фото»",
                "Could not get the image from Photos"
            )
            NSSound.beep()
            return
        }
        items.append(MosaicItem(
            sourceURL: URL(fileURLWithPath: suggestedName),
            image: loaded.nsImage,
            cgImage: loaded.cgImage,
            frameMM: CGRect(x: marginMM, y: marginMM, width: 40, height: 40)
        ))
        arrangeGrid()
        statusMessage = localized("Добавлено из приложения «Фото». Всего", "Added from Photos. Total") +
            ": \(items.count)"
    }

    func addPastedImage(data: Data, suggestedName: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let loaded = loadOrientedImage(
                from: source,
                displayURL: URL(fileURLWithPath: suggestedName)
              ) else {
            statusMessage = localized(
                "Буфер обмена не содержит поддерживаемого изображения",
                "The clipboard does not contain a supported image"
            )
            NSSound.beep()
            return
        }
        items.append(MosaicItem(
            sourceURL: URL(fileURLWithPath: suggestedName),
            image: loaded.nsImage,
            cgImage: loaded.cgImage,
            frameMM: CGRect(x: marginMM, y: marginMM, width: 40, height: 40)
        ))
        arrangeGrid()
        statusMessage = localized("Вставлено из буфера обмена. Всего", "Pasted from clipboard. Total") +
            ": \(items.count)"
    }

    func removeSelected() {
        guard let selectedItemID else { return }
        items.removeAll { $0.id == selectedItemID }
        self.selectedItemID = nil
        if layoutMode == .grid { arrangeGrid() }
    }

    func beginManualEditing() {
        layoutMode = .free
    }

    func scaleSelected(by requestedFactor: CGFloat) {
        guard let selectedItemID,
              let index = items.firstIndex(where: { $0.id == selectedItemID }) else { return }
        beginManualEditing()

        let paper = paperSizeMM
        let frame = items[index].frameMM
        let minimumFactor = max(10 / max(frame.width, 1), 10 / max(frame.height, 1))
        let maximumFactor = min(
            paper.width / max(frame.width, 1),
            paper.height / max(frame.height, 1)
        )
        let factor = min(max(requestedFactor, minimumFactor), maximumFactor)
        let newSize = CGSize(width: frame.width * factor, height: frame.height * factor)
        let desiredOrigin = CGPoint(
            x: frame.midX - newSize.width / 2,
            y: frame.midY - newSize.height / 2
        )
        items[index].frameMM = CGRect(
            x: min(max(0, desiredOrigin.x), max(0, paper.width - newSize.width)),
            y: min(max(0, desiredOrigin.y), max(0, paper.height - newSize.height)),
            width: newSize.width,
            height: newSize.height
        )
        pushOverlappingPhotos(awayFrom: selectedItemID)
    }

    func snappedFrame(_ proposed: CGRect, excluding itemID: UUID) -> CGRect {
        guard snapEnabled else { return proposed }
        let threshold: CGFloat = 5
        let paper = paperSizeMM
        var result = proposed

        var xCandidates: [CGFloat] = [0, paper.width - proposed.width]
        var yCandidates: [CGFloat] = [0, paper.height - proposed.height]

        for other in items where other.id != itemID {
            let overlapsVertically = proposed.maxY > other.frameMM.minY && proposed.minY < other.frameMM.maxY
            let overlapsHorizontally = proposed.maxX > other.frameMM.minX && proposed.minX < other.frameMM.maxX
            if overlapsVertically {
                xCandidates.append(contentsOf: [
                    other.frameMM.minX,
                    other.frameMM.maxX,
                    other.frameMM.minX - proposed.width,
                    other.frameMM.maxX - proposed.width
                ])
            }
            if overlapsHorizontally {
                yCandidates.append(contentsOf: [
                    other.frameMM.minY,
                    other.frameMM.maxY,
                    other.frameMM.minY - proposed.height,
                    other.frameMM.maxY - proposed.height
                ])
            }
        }

        if let nearestX = xCandidates.min(by: {
            abs($0 - proposed.minX) < abs($1 - proposed.minX)
        }), abs(nearestX - proposed.minX) <= threshold {
            result.origin.x = nearestX
        }
        if let nearestY = yCandidates.min(by: {
            abs($0 - proposed.minY) < abs($1 - proposed.minY)
        }), abs(nearestY - proposed.minY) <= threshold {
            result.origin.y = nearestY
        }

        result.origin.x = min(max(0, result.origin.x), max(0, paper.width - result.width))
        result.origin.y = min(max(0, result.origin.y), max(0, paper.height - result.height))
        return result
    }

    func pushOverlappingPhotos(awayFrom selectedID: UUID) {
        guard snapEnabled,
              let selectedFrame = items.first(where: { $0.id == selectedID })?.frameMM else { return }

        var queue: [UUID] = [selectedID]
        var iterations = 0
        let iterationLimit = max(20, items.count * items.count * 3)

        while !queue.isEmpty && iterations < iterationLimit {
            iterations += 1
            let anchorID = queue.removeFirst()
            guard let anchorFrame = items.first(where: { $0.id == anchorID })?.frameMM else { continue }

            for index in items.indices {
                let otherID = items[index].id
                guard otherID != anchorID, otherID != selectedID else { continue }
                let otherFrame = items[index].frameMM
                guard overlapArea(anchorFrame, otherFrame) > 0.05 else { continue }

                if let newFrame = bestPushedFrame(
                    for: otherFrame,
                    itemID: otherID,
                    awayFrom: anchorFrame,
                    anchorID: anchorID,
                    protectedFrame: selectedFrame
                ), distance(from: otherFrame.origin, to: newFrame.origin) > 0.01 {
                    items[index].frameMM = newFrame
                    queue.append(otherID)
                }
            }
        }
    }

    private func bestPushedFrame(
        for frame: CGRect,
        itemID: UUID,
        awayFrom anchor: CGRect,
        anchorID: UUID,
        protectedFrame: CGRect
    ) -> CGRect? {
        let paper = paperSizeMM
        let candidates = [
            CGRect(x: anchor.maxX, y: frame.minY, width: frame.width, height: frame.height),
            CGRect(x: anchor.minX - frame.width, y: frame.minY, width: frame.width, height: frame.height),
            CGRect(x: frame.minX, y: anchor.maxY, width: frame.width, height: frame.height),
            CGRect(x: frame.minX, y: anchor.minY - frame.height, width: frame.width, height: frame.height)
        ].filter { candidate in
            candidate.minX >= 0 && candidate.minY >= 0 &&
            candidate.maxX <= paper.width && candidate.maxY <= paper.height &&
            (anchorID == selectedItemID || overlapArea(candidate, protectedFrame) <= 0.05)
        }

        return candidates.min { lhs, rhs in
            placementScore(lhs, original: frame, itemID: itemID, anchorID: anchorID) <
            placementScore(rhs, original: frame, itemID: itemID, anchorID: anchorID)
        }
    }

    private func placementScore(
        _ candidate: CGRect,
        original: CGRect,
        itemID: UUID,
        anchorID: UUID
    ) -> CGFloat {
        let collisions = items.reduce(CGFloat.zero) { total, item in
            guard item.id != itemID, item.id != anchorID else { return total }
            return total + overlapArea(candidate, item.frameMM)
        }
        return collisions * 10_000 + distance(from: candidate.origin, to: original.origin)
    }

    private func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    func removeAll() {
        items.removeAll()
        selectedItemID = nil
        statusMessage = localized("Лист очищен", "Sheet cleared")
    }

    func arrangeGrid() {
        guard !items.isEmpty else { return }
        let count = items.count
        let paper = paperSizeMM
        let ratio = Double(paper.width / paper.height)
        let columns = max(1, Int(ceil(sqrt(Double(count) * ratio))))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let usableWidth = max(10, paper.width - marginMM * 2 - gapMM * CGFloat(columns - 1))
        let usableHeight = max(10, paper.height - marginMM * 2 - gapMM * CGFloat(rows - 1))
        let cellWidth = usableWidth / CGFloat(columns)
        let cellHeight = usableHeight / CGFloat(rows)

        for index in items.indices {
            let column = index % columns
            let row = index / columns
            let imageRatio = CGFloat(items[index].cgImage.width) / CGFloat(items[index].cgImage.height)
            let cellRatio = cellWidth / cellHeight
            let fittedWidth: CGFloat
            let fittedHeight: CGFloat
            if imageRatio > cellRatio {
                fittedWidth = cellWidth
                fittedHeight = cellWidth / imageRatio
            } else {
                fittedHeight = cellHeight
                fittedWidth = cellHeight * imageRatio
            }
            let cellX = marginMM + CGFloat(column) * (cellWidth + gapMM)
            let cellY = marginMM + CGFloat(row) * (cellHeight + gapMM)
            items[index].frameMM = CGRect(
                x: cellX + (cellWidth - fittedWidth) / 2,
                y: cellY + (cellHeight - fittedHeight) / 2,
                width: fittedWidth,
                height: fittedHeight
            )
        }
    }

    func autoArrange() {
        guard !items.isEmpty else {
            statusMessage = localized("Сначала добавьте фотографии", "Add photos first")
            return
        }
        arrangeGrid()
        if layoutMode == .grid {
            statusMessage = localized(
                "Фотографии автоматически размещены по ровной сетке",
                "Photos were automatically arranged in an even grid"
            )
        } else {
            statusMessage = localized(
                "Фотографии автоматически размещены и доступны для ручной правки",
                "Photos were automatically arranged and remain editable"
            )
        }
    }

    func paperSettingsChanged() {
        if layoutMode == .grid { arrangeGrid() }
    }

    func save() {
        guard !items.isEmpty else {
            statusMessage = localized("Добавьте фотографии на лист", "Add photos to the sheet")
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.title = localized("Сохранить лист мозаики", "Save mosaic sheet")
        panel.prompt = localized("Сохранить", "Save")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [exportFormat.contentType]
        panel.nameFieldStringValue = "mosaic_\(paperPresetID.uppercased()).\(exportFormat.fileExtension)"
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let url = selectedURL.deletingPathExtension().appendingPathExtension(exportFormat.fileExtension)

        do {
            let rendered = try renderSheet()
            switch exportFormat {
            case .pdf:
                try writePDF(rendered, to: url)
            case .jpeg, .png:
                try writeRaster(rendered, to: url)
            }
            statusMessage = localized("Сохранено", "Saved") + ": \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            statusMessage = localized("Ошибка сохранения", "Save error") + ": \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func loadOrientedImage(from url: URL) -> (cgImage: CGImage, nsImage: NSImage)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return loadOrientedImage(from: source, displayURL: url)
    }

    private func loadOrientedImage(
        from source: CGImageSource,
        displayURL: URL
    ) -> (cgImage: CGImage, nsImage: NSImage)? {
        guard let input = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        var ciImage = CIImage(cgImage: input).oriented(forExifOrientation: orientation)
        ciImage = ciImage.transformed(
            by: CGAffineTransform(translationX: -ciImage.extent.minX, y: -ciImage.extent.minY)
        )
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return (cgImage, nsImage)
    }

    private func renderSheet() throws -> CGImage {
        let targetWidth = Int(outputPixelSize.width)
        let targetHeight = Int(outputPixelSize.height)
        guard targetWidth <= 40_000, targetHeight <= 40_000,
              targetWidth * targetHeight <= 220_000_000,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ExportError.invalidSize }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.interpolationQuality = .high
        let scaleX = CGFloat(targetWidth) / paperSizeMM.width
        let scaleY = CGFloat(targetHeight) / paperSizeMM.height

        for item in items {
            let frame = CGRect(
                x: item.frameMM.minX * scaleX,
                y: CGFloat(targetHeight) - item.frameMM.maxY * scaleY,
                width: item.frameMM.width * scaleX,
                height: item.frameMM.height * scaleY
            )
            context.saveGState()
            context.clip(to: frame)
            let imageRatio = CGFloat(item.cgImage.width) / CGFloat(item.cgImage.height)
            let frameRatio = frame.width / frame.height
            let drawRect: CGRect
            if imageRatio > frameRatio {
                let height = frame.width / imageRatio
                drawRect = CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height)
            } else {
                let width = frame.height * imageRatio
                drawRect = CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
            }
            context.draw(item.cgImage, in: drawRect)
            context.restoreGState()
        }

        guard let image = context.makeImage() else { throw ExportError.renderFailed }
        return image
    }

    private func writeRaster(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            exportFormat.contentType.identifier as CFString,
            1,
            nil
        ) else { throw ExportError.unsupportedFormat }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        if exportFormat == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.writeFailed }
    }

    private func writePDF(_ image: CGImage, to url: URL) throws {
        var pageRect = CGRect(
            x: 0,
            y: 0,
            width: paperSizeMM.width / 25.4 * 72,
            height: paperSizeMM.height / 25.4 * 72
        )
        guard let context = CGContext(url as CFURL, mediaBox: &pageRect, nil) else {
            throw ExportError.writeFailed
        }
        context.beginPDFPage(nil)
        context.interpolationQuality = .high
        context.draw(image, in: pageRect)
        context.endPDFPage()
        context.closePDF()
    }
}
