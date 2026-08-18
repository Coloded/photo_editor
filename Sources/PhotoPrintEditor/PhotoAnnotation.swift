import AppKit
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case blur = "Размытие"
    case line = "Линия"
    case arrow = "Стрелка"
    case rectangle = "Квадрат"
    case ellipse = "Круг"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .blur: "drop.halffull"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        guard language == .en else { return rawValue }
        return switch self {
        case .blur: "Blur"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Circle"
        }
    }
}

struct AnnotationColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct PhotoAnnotation: Identifiable {
    let id = UUID()
    let tool: EditorTool
    let start: CGPoint
    let end: CGPoint
    let color: AnnotationColor
    let relativeLineWidth: CGFloat
}

enum AnnotationRenderer {
    static func draw(_ annotation: PhotoAnnotation, in rect: CGRect, context: CGContext) {
        guard annotation.tool != .blur else { return }
        let start = point(annotation.start, in: rect)
        let end = point(annotation.end, in: rect)
        let lineWidth = max(1, annotation.relativeLineWidth * min(rect.width, rect.height))

        context.saveGState()
        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.tool {
        case .line:
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        case .arrow:
            drawArrow(from: start, to: end, lineWidth: lineWidth, context: context)
        case .rectangle:
            context.stroke(rectangle(from: start, to: end))
        case .ellipse:
            context.strokeEllipse(in: rectangle(from: start, to: end))
        case .blur:
            break
        }
        context.restoreGState()
    }

    private static func point(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.maxY - normalized.y * rect.height
        )
    }

    private static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private static func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat,
        context: CGContext
    ) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, lineWidth * 4.5)
        let spread = CGFloat.pi / 7
        let left = CGPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        )
        context.move(to: left)
        context.addLine(to: end)
        context.addLine(to: right)
        context.strokePath()
    }
}
