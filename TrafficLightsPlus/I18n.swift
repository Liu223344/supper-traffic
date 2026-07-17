import Foundation

enum I18n {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizationBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func string(_ key: String, language: String) -> String {
        let path = localizationBundle.path(forResource: language, ofType: "lproj")
            ?? localizationBundle.path(forResource: language.lowercased(), ofType: "lproj")
        guard let path,
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static var localizationBundle: Bundle {
#if SWIFT_PACKAGE
        Bundle.module
#else
        Bundle.main
#endif
    }
}
