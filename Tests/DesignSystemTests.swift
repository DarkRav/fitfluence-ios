@testable import FitfluenceApp
import XCTest

final class DesignSystemTests: XCTestCase {
    func testThemeRadiiMatchDesignSpec() {
        XCTAssertEqual(FFTheme.Radius.card, 16)
        XCTAssertEqual(FFTheme.Radius.control, 12)
    }

    func testSpacingScaleIsStable() {
        XCTAssertEqual(FFSpacing.xxs, 4)
        XCTAssertEqual(FFSpacing.xs, 8)
        XCTAssertEqual(FFSpacing.sm, 12)
        XCTAssertEqual(FFSpacing.md, 16)
        XCTAssertEqual(FFSpacing.lg, 24)
        XCTAssertEqual(FFSpacing.xl, 32)
    }
}
