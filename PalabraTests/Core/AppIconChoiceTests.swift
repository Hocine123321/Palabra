import UIKit
import XCTest
@testable import Palabra

final class AppIconChoiceTests: XCTestCase {
    private let bundle = Bundle(for: AppEnvironment.self)

    func testRecortesIsThePrimaryIcon() {
        XCTAssertNil(AppIconChoice.recortes.alternateName)
        XCTAssertEqual(AppIconChoice(alternateName: nil), .recortes)
    }

    func testEveryAlternateRoundTripsAndNamesAreUnique() {
        let names = AppIconChoice.allCases.compactMap(\.alternateName)
        XCTAssertEqual(names.count, AppIconChoice.allCases.count - 1)
        XCTAssertEqual(Set(names).count, names.count)
        for choice in AppIconChoice.allCases {
            XCTAssertEqual(AppIconChoice(alternateName: choice.alternateName), choice)
        }
    }

    func testUnknownNameFallsBackToThePrimaryIcon() {
        XCTAssertEqual(AppIconChoice(alternateName: "RemovedInALaterVersion"), .recortes)
    }

    func testEveryChoiceHasAPreviewImage() {
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: choice.previewAsset, in: bundle, compatibleWith: nil), choice.previewAsset)
        }
    }

    /// Guards project.yml: every alternate must be listed in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES, or iOS refuses the switch.
    func testEveryAlternateIsRegisteredInInfoPlist() throws {
        let icons = try XCTUnwrap(bundle.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
        for name in AppIconChoice.allCases.compactMap(\.alternateName) {
            XCTAssertNotNil(alternates[name], name)
        }
    }
}
