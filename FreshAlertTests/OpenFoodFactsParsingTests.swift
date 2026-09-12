import XCTest
@testable import FreshAlert

/// Reine Funktionen des Dienstes: URL-Aufbau für die v2-API und das Übersetzen
/// der Antwort. Der Netzweg selbst wird nicht getestet.
final class OpenFoodFactsParsingTests: XCTestCase {

    func testProductURLUsesV2WithFields() {
        let url = OpenFoodFactsService.productURL(barcode: "4000000000000", host: "world.openfoodfacts.org")
        XCTAssertEqual(
            url?.absoluteString,
            "https://world.openfoodfacts.org/api/v2/product/4000000000000?fields=product_name,product_name_de,brands,image_front_small_url,categories_tags"
        )
    }

    func testChainCoversAllThreeDatabases() {
        XCTAssertEqual(OpenFoodFactsService.hosts, [
            "world.openfoodfacts.org", "world.openproductsfacts.org", "world.openbeautyfacts.org",
        ])
    }

    func testUserAgentNamesAppAndContact() {
        XCTAssertTrue(OpenFoodFactsService.userAgent.hasPrefix("FreshAlert/"))
        XCTAssertTrue(OpenFoodFactsService.userAgent.hasSuffix("(ios; ze.d@me.com)"))
    }

    func testGermanNameWins() throws {
        let json = """
        {"status":1,"product":{"product_name":"Oat Drink","product_name_de":"Haferdrink","brands":"Oatly","image_front_small_url":"https://img/x.jpg"}}
        """
        let info = try XCTUnwrap(OpenFoodFactsService.productInfo(from: Data(json.utf8)))
        XCTAssertEqual(info.name, "Haferdrink")
        XCTAssertEqual(info.brand, "Oatly")
        XCTAssertEqual(info.imageURL, "https://img/x.jpg")
    }

    func testEmptyGermanNameFallsBackToGeneralName() throws {
        let json = #"{"status":1,"product":{"product_name":"Oat Drink","product_name_de":""}}"#
        let info = try XCTUnwrap(OpenFoodFactsService.productInfo(from: Data(json.utf8)))
        XCTAssertEqual(info.name, "Oat Drink")
        XCTAssertEqual(info.brand, "")
        XCTAssertNil(info.imageURL)
    }

    func testStatusZeroMeansNotFoundOnThisHost() throws {
        let json = #"{"status":0,"status_verbose":"product not found"}"#
        XCTAssertNil(try OpenFoodFactsService.productInfo(from: Data(json.utf8)))
    }

    func testGarbageIsAnInvalidResponse() {
        XCTAssertThrowsError(try OpenFoodFactsService.productInfo(from: Data("<html>".utf8))) { error in
            guard case OFFError.invalidResponse = error else {
                return XCTFail("Erwartet invalidResponse, bekommen \(error)")
            }
        }
    }

    func testOnlyProductNotFoundCountsAsNotFound() {
        XCTAssertTrue(OFFError.productNotFound.isProductNotFound)
        XCTAssertFalse(OFFError.invalidResponse.isProductNotFound)
        XCTAssertFalse(OFFError.network(URLError(.notConnectedToInternet)).isProductNotFound)
    }

    func testContributeURLCarriesBarcode() {
        XCTAssertEqual(
            Legal.openFoodFactsContributeURL(barcode: "4000000000000")?.absoluteString,
            "https://world.openfoodfacts.org/cgi/product.pl?type=add&code=4000000000000"
        )
    }
}
