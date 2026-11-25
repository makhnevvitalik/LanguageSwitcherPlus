// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation

public final class UserDefaultsModifierTapPreferences {
    public static let durationOptions = (1...10).map { Double($0) / 10 }
    public static let defaultDuration: TimeInterval = 0.3

    private enum Keys {
        static let maximumDuration = "keyboardSwitching.maximumTapDuration"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var maximumDuration: TimeInterval {
        get {
            if let stored = validDuration(forKey: Keys.maximumDuration) {
                return stored
            }
            return Self.defaultDuration
        }
        set {
            guard Self.durationOptions.contains(newValue) else {
                return
            }
            userDefaults.set(newValue, forKey: Keys.maximumDuration)
        }
    }

    private func validDuration(forKey key: String) -> TimeInterval? {
        guard userDefaults.object(forKey: key) != nil else {
            return nil
        }
        let stored = userDefaults.double(forKey: key)
        return Self.durationOptions.contains(stored) ? stored : nil
    }
}
