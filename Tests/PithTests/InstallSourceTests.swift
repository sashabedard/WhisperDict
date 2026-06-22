// Pith — on-device push-to-talk dictation for macOS
// Copyright (C) 2026 Sasha Bédard
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
