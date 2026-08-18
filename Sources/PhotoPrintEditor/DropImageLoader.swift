import AppKit
import UniformTypeIdentifiers

struct DroppedImagePayload: @unchecked Sendable {
    let data: Data
    let suggestedName: String
}

private final class ItemProviderBox: @unchecked Sendable {
    let provider: NSItemProvider

    init(_ provider: NSItemProvider) {
        self.provider = provider
    }
}

enum DropImageLoader {
    static let acceptedTypes: [UTType] = [
        .fileURL, .image, .jpeg, .png, .heic, .tiff, .bmp, .gif
    ]

    static func load(
        from provider: NSItemProvider,
        completion: @escaping @Sendable (Result<DroppedImagePayload, Error>) -> Void
    ) {
        let box = ItemProviderBox(provider)
        let suggestedName = provider.suggestedName
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   let imageData = try? Data(contentsOf: url) {
                    completion(.success(DroppedImagePayload(
                        data: imageData,
                        suggestedName: url.lastPathComponent
                    )))
                } else {
                    loadImageRepresentation(
                        from: box,
                        suggestedName: suggestedName,
                        completion: completion
                    )
                }
            }
        } else {
            loadImageRepresentation(
                from: box,
                suggestedName: suggestedName,
                completion: completion
            )
        }
    }

    private static func loadImageRepresentation(
        from box: ItemProviderBox,
        suggestedName: String?,
        completion: @escaping @Sendable (Result<DroppedImagePayload, Error>) -> Void
    ) {
        let provider = box.provider
        let identifier = preferredImageIdentifier(for: provider)
        guard let identifier else {
            completion(.failure(DropError.unsupportedImage))
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
            if let url, let data = try? Data(contentsOf: url) {
                let name = suggestedName ?? url.lastPathComponent
                completion(.success(DroppedImagePayload(data: data, suggestedName: name)))
                return
            }

            box.provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data else {
                    completion(.failure(DropError.cannotReadImage))
                    return
                }
                let name = suggestedName ?? "photo-from-photos"
                completion(.success(DroppedImagePayload(data: data, suggestedName: name)))
            }
        }
    }

    private static func preferredImageIdentifier(for provider: NSItemProvider) -> String? {
        let preferred = [UTType.heic, .jpeg, .png, .tiff, .bmp, .gif, .image]
        for type in preferred where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let exact = provider.registeredTypeIdentifiers.first(where: {
                guard let registered = UTType($0) else { return false }
                return registered.conforms(to: type) && registered.conforms(to: .image)
            }) {
                return exact
            }
            return type.identifier
        }
        return provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        })
    }
}

private enum DropError: LocalizedError {
    case unsupportedImage
    case cannotReadImage

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            localized("Перетаскиваемый объект не содержит изображения", "The dragged item does not contain an image")
        case .cannotReadImage:
            localized("Не удалось получить изображение из приложения «Фото»", "Could not get the image from Photos")
        }
    }
}
