import XCTest
@testable import Pith

final class InstallSourceTests: XCTestCase {

    func testHomebrewDetectedWhenCaskroomPathExists() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PithTests-caskroom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let saved = InstallSource.caskroomPaths
        defer { InstallSource.caskroomPaths = saved }
        InstallSource.caskroomPaths = [dir.path]

        XCTAssertTrue(InstallSource.isHomebrewManaged())
    }

    func testNotHomebrewWhenNoCaskroomPath() {
        let saved = InstallSource.caskroomPaths
        defer { InstallSource.caskroomPaths = saved }
        InstallSource.caskroomPaths = ["/nonexistent/pith-\(UUID().uuidString)"]

        XCTAssertFalse(InstallSource.isHomebrewManaged())
    }
}
