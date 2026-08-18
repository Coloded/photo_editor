import SwiftUI

struct MosaicCanvasView: View {
    @ObservedObject var model: MosaicModel

    var body: some View {
        GeometryReader { proxy in
            let paper = model.paperSizeMM
            let scale = min(proxy.size.width / paper.width, proxy.size.height / paper.height)
            let canvasSize = CGSize(width: paper.width * scale, height: paper.height * scale)

            ZStack(alignment: .topLeading) {
                Color.white

                ForEach($model.items) { $item in
                    let itemID = item.id
                    MosaicItemView(
                        item: $item,
                        paperSizeMM: paper,
                        scale: scale,
                        isSelected: model.selectedItemID == itemID,
                        canEdit: model.layoutMode == .free,
                        select: { model.selectedItemID = itemID },
                        snap: { proposed in
                            model.snappedFrame(proposed, excluding: itemID)
                        },
                        pushNeighbors: { model.pushOverlappingPhotos(awayFrom: itemID) }
                    )
                    .zIndex(model.selectedItemID == itemID ? 1 : 0)
                }
            }
            .coordinateSpace(name: "mosaicCanvas")
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
            .shadow(color: .black.opacity(0.22), radius: 18, y: 7)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct MosaicItemView: View {
    @Binding var item: MosaicItem
    let paperSizeMM: CGSize
    let scale: CGFloat
    let isSelected: Bool
    let canEdit: Bool
    let select: () -> Void
    let snap: (CGRect) -> CGRect
    let pushNeighbors: () -> Void

    @State private var dragStartFrame: CGRect?
    @State private var resizeStartFrame: CGRect?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: item.frameMM.width * scale, height: item.frameMM.height * scale)
                .contentShape(Rectangle())
                .overlay {
                    Rectangle()
                        .stroke(
                            isSelected ? Color.accentColor : Color.white.opacity(0.55),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .gesture(canEdit ? moveGesture : nil)
                .onTapGesture(perform: select)

            if isSelected && canEdit {
                ZStack {
                    Circle().fill(Color.accentColor)
                    Circle().stroke(.white, lineWidth: 2)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .offset(x: 10, y: 10)
                .contentShape(Circle())
                .gesture(resizeGesture)
            }
        }
        .frame(width: item.frameMM.width * scale, height: item.frameMM.height * scale)
        .position(
            x: item.frameMM.midX * scale,
            y: item.frameMM.midY * scale
        )
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("mosaicCanvas"))
            .onChanged { value in
                select()
                if dragStartFrame == nil {
                    dragStartFrame = item.frameMM
                }
                guard let start = dragStartFrame else { return }
                let dx = value.translation.width / scale
                let dy = value.translation.height / scale
                let maxX = max(0, paperSizeMM.width - start.width)
                let maxY = max(0, paperSizeMM.height - start.height)
                let proposed = CGRect(
                    x: min(max(0, start.minX + dx), maxX),
                    y: min(max(0, start.minY + dy), maxY),
                    width: start.width,
                    height: start.height
                )
                item.frameMM = snap(proposed)
                pushNeighbors()
            }
            .onEnded { _ in dragStartFrame = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("mosaicCanvas"))
            .onChanged { value in
                if resizeStartFrame == nil {
                    resizeStartFrame = item.frameMM
                    select()
                }
                guard let start = resizeStartFrame else { return }
                let aspect = max(0.05, start.width / start.height)
                let requestedWidth = max(10, start.width + value.translation.width / scale)
                let maxWidthByPaper = paperSizeMM.width - start.minX
                let maxWidthByHeight = (paperSizeMM.height - start.minY) * aspect
                let newWidth = min(requestedWidth, maxWidthByPaper, maxWidthByHeight)
                item.frameMM.size.width = newWidth
                item.frameMM.size.height = newWidth / aspect
                pushNeighbors()
            }
            .onEnded { _ in resizeStartFrame = nil }
    }
}
