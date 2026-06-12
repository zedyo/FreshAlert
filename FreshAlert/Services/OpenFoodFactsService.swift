import Foundation

struct ProductInfo {
    let name: String
    let brand: String
    let imageURL: String?
    let quantity: String?
}

actor OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let baseURL = "https://world.openfoodfacts.org/api/v0/product"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    func fetchProduct(barcode: String) async throws -> ProductInfo {
        // Eingang validieren bevor in die URL gebaut wird. Der Scanner
        // akzeptiert auch QR-/Code128-Payloads, die theoretisch
        // Pfad-/Query-Zeichen enthalten könnten. Open-Food-Facts-Codes sind
        // numerische GTINs (EAN-8/13, UPC) — ein ASCII-Ziffern-Check ist
        // damit funktional ausreichend UND blockt Injection-Versuche.
        let trimmed = barcode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.count <= 20,
              trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw OFFError.invalidBarcode
        }
        guard let url = URL(string: "\(baseURL)/\(trimmed).json") else {
            throw OFFError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OFFError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else {
            throw OFFError.productNotFound
        }
        let name = product.productNameDe
            ?? product.productName
            ?? product.genericName
            ?? "Unbekanntes Produkt"
        return ProductInfo(
            name: name,
            brand: product.brands ?? "",
            imageURL: product.imageFrontURL ?? product.imageURL,
            quantity: product.quantity
        )
    }
}

enum OFFError: LocalizedError {
    case invalidBarcode
    case invalidURL
    case invalidResponse
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:   return "Ungültiger Barcode"
        case .invalidURL:       return "Ungültige URL"
        case .invalidResponse:  return "Ungültige Server-Antwort"
        case .productNotFound:  return "Produkt nicht in der Datenbank gefunden"
        }
    }
}

// MARK: - Decodable Responses
private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let productNameDe: String?
    let genericName: String?
    let brands: String?
    let imageURL: String?
    let imageFrontURL: String?
    let quantity: String?

    enum CodingKeys: String, CodingKey {
        case productName    = "product_name"
        case productNameDe  = "product_name_de"
        case genericName    = "generic_name"
        case brands
        case imageURL       = "image_url"
        case imageFrontURL  = "image_front_url"
        case quantity
    }
}
