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
        guard let url = URL(string: "\(baseURL)/\(barcode).json") else {
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
    case invalidURL
    case invalidResponse
    case productNotFound

    var errorDescription: String? {
        switch self {
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
