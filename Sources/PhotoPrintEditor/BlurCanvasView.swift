import AppKit
import SwiftUI

struct BlurCanvasView: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeNSView(context: Context) -> BlurImageView {
        let view = BlurImageView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: BlurImageView, context: Context) {
        nsView.model = model
        nsView.image = model.previewImage
        nsView.brushLevel = model.brushLevel
        nsView.activeTool = model.activeTool
        nsView.lineWidth = model.lineWidth
        nsView.drawingColor = model.drawingColor
        nsView.annotations = model.annotations
        nsView.needsDisplay = true
    }
}

final class BlurImageView: NSView {
    weak var model: EditorModel?
    var image: NSImage?
    var brushLevel = 4
    var activeTool: EditorTool = .blur
    var lineWidth = 4
    var drawingColor: NSColor = .systemRed
    var annotations: [PhotoAnnotation] = []
    private var cursorPoint: CGPoint?
    private var lastPaintPoint: CGPoint?
    private var draftStart: CGPoint?
    private var draftEnd: CGPoint?
    private var trackingAreaReference: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        guard let image else { return }
        let rect = imageRect(for: image)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

        if let context = NSGraphicsContext.current?.cgContext {
            for annotation in annotations {
                AnnotationRenderer.draw(annotation, in: rect, context: context)
            }
            if let draftStart, let draftEnd, activeTool != .blur {
                let draft = PhotoAnnotation(
                    tool: activeTool,
                    start: draftStart,
                    end: draftEnd,
                    color: AnnotationColor(drawingColor),
                    relativeLineWidth: CGFloat(lineWidth) / 500
                )
                AnnotationRenderer.draw(draft, in: rect, context: context)
            }
        }

        if let cursorPoint, rect.contains(cursorPoint) {
            if activeTool == .blur {
                let diameter = brushDiameter(in: rect)
                let indicator = NSBezierPath(ovalIn: CGRect(
                    x: cursorPoint.x - diameter / 2,
                    y: cursorPoint.y - diameter / 2,
                    width: diameter,
                    height: diameter
                ))
                NSColor.white.withAlphaComponent(0.85).setStroke()
                indicator.lineWidth = 2
                indicator.stroke()
                NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
                indicator.lineWidth = 1
                indicator.stroke()
            } else {
                let crosshair = NSBezierPath()
                crosshair.move(to: CGPoint(x: cursorPoint.x - 7, y: cursorPoint.y))
                crosshair.line(to: CGPoint(x: cursorPoint.x + 7, y: cursorPoint.y))
                crosshair.move(to: CGPoint(x: cursorPoint.x, y: cursorPoint.y - 7))
                crosshair.line(to: CGPoint(x: cursorPoint.x, y: cursorPoint.y + 7))
                drawingColor.setStroke()
                crosshair.lineWidth = 1.5
                crosshair.stroke()
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        cursorPoint = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        lastPaintPoint = nil
        let point = convert(event.locationInWindow, from: nil)
        if activeTool == .blur {
            paint(at: point)
        } else if let normalized = normalizedPoint(for: point) {
            draftStart = normalized
            draftEnd = normalized
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if activeTool == .blur {
            paint(at: point)
        } else if let normalized = normalizedPoint(for: point) {
            draftEnd = normalized
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        lastPaintPoint = nil
        if activeTool != .blur, let draftStart, let draftEnd {
            model?.addAnnotation(tool: activeTool, start: draftStart, end: draftEnd)
        }
        draftStart = nil
        draftEnd = nil
        needsDisplay = true
    }

    private func paint(at point: CGPoint) {
        guard let image, let model else { return }
        let rect = imageRect(for: image)
        guard rect.contains(point) else { return }

        if let lastPaintPoint {
            let distance = hypot(point.x - lastPaintPoint.x, point.y - lastPaintPoint.y)
            if distance < brushDiameter(in: rect) * 0.18 { return }
        }
        lastPaintPoint = point

        let normalized = CGPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (rect.maxY - point.y) / rect.height
        )
        model.applyBlur(at: normalized)
    }

    private func normalizedPoint(for point: CGPoint) -> CGPoint? {
        guard let image else { return nil }
        let rect = imageRect(for: image)
        guard rect.contains(point) else { return nil }
        return CGPoint(
            x: min(max((point.x - rect.minX) / rect.width, 0), 1),
            y: min(max((rect.maxY - point.y) / rect.height, 0), 1)
        )
    }

    private func imageRect(for image: NSImage) -> CGRect {
        let imageRatio = image.size.width / image.size.height
        let viewRatio = bounds.width / max(bounds.height, 1)
        if imageRatio > viewRatio {
            let height = bounds.width / imageRatio
            return CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        } else {
            let width = bounds.height * imageRatio
            return CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
        }
    }

    private func brushDiameter(in imageRect: CGRect) -> CGFloat {
        min(imageRect.width, imageRect.height) * (0.024 + CGFloat(brushLevel) * 0.018)
    }
}
