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

import Foundation

/// Maps a raw audio RMS amplitude to a normalized [0, 1] level for the
/// equalizer bars. Loudness is perceived logarithmically, so we map through a
/// dB curve and apply asymmetric smoothing (fast rise, slow fall) so the bars
/// feel lively without jittering.
struct LevelMeter {
    /// RMS (in dB) treated as silence (→ 0).
    static let floorDB: Float = -50
    /// RMS (in dB) treated as full scale (→ 1).
    static let ceilDB: Float = -10
    /// Smoothing toward a higher level (fast).
    static let attack: Float = 0.6
    /// Smoothing toward a lower level (slow).
    static let release: Float = 0.15

    private var smoothed: Float = 0

    /// Pure log-scaled, clamped mapping. No state.
    static func normalize(rms: Float) -> Float {
        let safe = max(rms, 1e-7)
        let db = 20 * log10(safe)
        let norm = (db - floorDB) / (ceilDB - floorDB)
        return min(max(norm, 0), 1)
    }

    /// Stateful: normalize + asymmetric exponential smoothing.
    mutating func update(rms: Float) -> Float {
        smooth(Self.normalize(rms: rms))
    }

    /// Asymmetric exponential smoothing (fast attack, slow release) toward an
    /// already-normalized [0, 1] target. Used for per-band spectrum values that
    /// are pre-normalized and must not be log-scaled again.
    mutating func smooth(_ target: Float) -> Float {
        let t = min(max(target, 0), 1)
        let coeff = t > smoothed ? Self.attack : Self.release
        smoothed += (t - smoothed) * coeff
        return smoothed
    }
}
