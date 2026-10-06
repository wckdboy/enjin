import EnjinKit
import Foundation

extension String {
    /// Look this string up in the app's own language (which may differ from the
    /// device's). SwiftUI views get this for free from `.environment(\.locale)`;
    /// plain Strings need it explicitly.
    func localizedIn(_ language: AppLanguage) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return self }
        return bundle.localizedString(forKey: self, value: self, table: nil)
    }
}
