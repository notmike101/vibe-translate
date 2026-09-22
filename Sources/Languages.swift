import Foundation

/// A language the picker can offer. `auto` is a source-only sentinel: the Google
/// endpoint detects it server-side, and the chat providers are told to detect it
/// in the prompt.
struct Language: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let native: String

    var id: String { code }

    static let auto = Language(code: "auto", name: "Detect language", native: "Detect language")

    /// The English name a prompt should use: the catalog entry, then whatever
    /// `Locale` knows, then the raw code as a last resort.
    static func name(for code: String) -> String {
        if code == auto.code { return "the detected source language" }
        if let known = catalog.first(where: { $0.code == code }) { return known.name }
        if let localized = Locale(identifier: "en_US").localizedString(forLanguageCode: code) {
            return localized
        }
        return code
    }

    static func language(for code: String) -> Language {
        if code == auto.code { return auto }
        return catalog.first { $0.code == code } ?? Language(code: code, name: name(for: code), native: code)
    }

    static let catalog: [Language] = [
        Language(code: "ar", name: "Arabic", native: "العربية"),
        Language(code: "bn", name: "Bengali", native: "বাংলা"),
        Language(code: "bg", name: "Bulgarian", native: "Български"),
        Language(code: "zh-CN", name: "Chinese (Simplified)", native: "简体中文"),
        Language(code: "zh-TW", name: "Chinese (Traditional)", native: "繁體中文"),
        Language(code: "hr", name: "Croatian", native: "Hrvatski"),
        Language(code: "cs", name: "Czech", native: "Čeština"),
        Language(code: "da", name: "Danish", native: "Dansk"),
        Language(code: "nl", name: "Dutch", native: "Nederlands"),
        Language(code: "en", name: "English", native: "English"),
        Language(code: "et", name: "Estonian", native: "Eesti"),
        Language(code: "fi", name: "Finnish", native: "Suomi"),
        Language(code: "fr", name: "French", native: "Français"),
        Language(code: "de", name: "German", native: "Deutsch"),
        Language(code: "el", name: "Greek", native: "Ελληνικά"),
        Language(code: "he", name: "Hebrew", native: "עברית"),
        Language(code: "hi", name: "Hindi", native: "हिन्दी"),
        Language(code: "hu", name: "Hungarian", native: "Magyar"),
        Language(code: "id", name: "Indonesian", native: "Bahasa Indonesia"),
        Language(code: "it", name: "Italian", native: "Italiano"),
        Language(code: "ja", name: "Japanese", native: "日本語"),
        Language(code: "ko", name: "Korean", native: "한국어"),
        Language(code: "lv", name: "Latvian", native: "Latviešu"),
        Language(code: "lt", name: "Lithuanian", native: "Lietuvių"),
        Language(code: "ms", name: "Malay", native: "Bahasa Melayu"),
        Language(code: "no", name: "Norwegian", native: "Norsk"),
        Language(code: "fa", name: "Persian", native: "فارسی"),
        Language(code: "pl", name: "Polish", native: "Polski"),
        Language(code: "pt", name: "Portuguese", native: "Português"),
        Language(code: "pt-BR", name: "Portuguese (Brazil)", native: "Português (Brasil)"),
        Language(code: "ro", name: "Romanian", native: "Română"),
        Language(code: "ru", name: "Russian", native: "Русский"),
        Language(code: "sr", name: "Serbian", native: "Српски"),
        Language(code: "sk", name: "Slovak", native: "Slovenčina"),
        Language(code: "sl", name: "Slovenian", native: "Slovenščina"),
        Language(code: "es", name: "Spanish", native: "Español"),
        Language(code: "sw", name: "Swahili", native: "Kiswahili"),
        Language(code: "sv", name: "Swedish", native: "Svenska"),
        Language(code: "tl", name: "Tagalog", native: "Tagalog"),
        Language(code: "ta", name: "Tamil", native: "தமிழ்"),
        Language(code: "th", name: "Thai", native: "ไทย"),
        Language(code: "tr", name: "Turkish", native: "Türkçe"),
        Language(code: "uk", name: "Ukrainian", native: "Українська"),
        Language(code: "ur", name: "Urdu", native: "اردو"),
        Language(code: "vi", name: "Vietnamese", native: "Tiếng Việt"),
    ]

    /// Source side gets the detect sentinel; target side does not.
    static let sourceCatalog: [Language] = [auto] + catalog
}
