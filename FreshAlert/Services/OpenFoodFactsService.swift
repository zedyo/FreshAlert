import Foundation

struct ProductInfo {
    let name: String
    let brand: String
    let imageURL: String?
    /// `categories_tags` aus Open Food Facts, vom allgemeinen zum spezifischen
    /// Tag, etwa ["en:dairies", "en:fermented-milk-products", "en:yogurts"].
    let categoryTags: [String]

    init(name: String, brand: String, imageURL: String?, categoryTags: [String] = []) {
        self.name = name
        self.brand = brand
        self.imageURL = imageURL
        self.categoryTags = categoryTags
    }

    /// Vorschlag für die Haltbarkeit, aus der Kategorie abgeleitet.
    var shelfLife: ShelfLife? { ShelfLifeSuggestion.suggestion(for: categoryTags) }
}

/// Sucht einen Barcode nacheinander in Open Food Facts, Open Products Facts und
/// Open Beauty Facts (alle drei mit derselben v2-API). "Nicht gefunden" auf
/// einem Host heißt: nächster Host. Netz- und Serverfehler brechen die Kette ab
/// und kommen als `OFFError.network` bzw. `.invalidResponse` an, damit die
/// Oberfläche sie vom echten "unbekannt" unterscheiden kann.
actor OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    static let hosts = [
        "world.openfoodfacts.org",
        "world.openproductsfacts.org",
        "world.openbeautyfacts.org",
    ]
    static let fields = "product_name,product_name_de,brands,image_front_small_url,categories_tags"

    /// Pflicht laut Open-Food-Facts-Nutzungsbedingungen: App, Version, Kontakt.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "FreshAlert/\(version) (ios; ze.d@me.com)"
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: config)
    }

    func fetchProduct(barcode: String) async throws -> ProductInfo {
        for host in Self.hosts {
            if let info = try await fetchProduct(barcode: barcode, host: host) {
                return info
            }
        }
        throw OFFError.productNotFound
    }

    /// `nil` heißt: dieser Host kennt den Barcode nicht.
    private func fetchProduct(barcode: String, host: String) async throws -> ProductInfo? {
        guard let url = Self.productURL(barcode: barcode, host: host) else {
            throw OFFError.invalidURL
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw OFFError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw OFFError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw OFFError.invalidResponse }
        return try Self.productInfo(from: data)
    }

    static func productURL(barcode: String, host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v2/product/\(barcode)"
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return components.url
    }

    /// Antwort der v2-API in `ProductInfo` übersetzen. `nil`, wenn der Host das
    /// Produkt nicht kennt (`status` 0). Deutscher Name vor dem allgemeinen.
    static func productInfo(from data: Data) throws -> ProductInfo? {
        let decoded: OFFResponse
        do {
            decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        } catch {
            throw OFFError.invalidResponse
        }
        guard decoded.status == 1, let product = decoded.product else { return nil }
        let name = nonEmpty(product.productNameDe)
            ?? nonEmpty(product.productName)
            ?? "Unbekanntes Produkt"
        return ProductInfo(
            name: name,
            brand: nonEmpty(product.brands) ?? "",
            imageURL: nonEmpty(product.imageFrontSmallURL),
            categoryTags: product.categoriesTags ?? []
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum OFFError: LocalizedError {
    case invalidURL
    case invalidResponse
    case network(Error)
    case productNotFound

    /// Alles außer "nicht gefunden" ist ein Verbindungsproblem: die Oberfläche
    /// geht dann den Offline-Weg statt zum Nachtragen aufzufordern.
    var isProductNotFound: Bool {
        if case .productNotFound = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Ungültige URL"
        case .invalidResponse:  return "Ungültige Server-Antwort"
        case .network:          return "Keine Verbindung zur Produktdatenbank"
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
    let brands: String?
    let imageFrontSmallURL: String?
    let categoriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case productName        = "product_name"
        case productNameDe      = "product_name_de"
        case brands
        case imageFrontSmallURL = "image_front_small_url"
        case categoriesTags     = "categories_tags"
    }
}
