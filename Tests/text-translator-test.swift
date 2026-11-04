import Foundation

@main
struct TextTranslatorTest {
    static func main() {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures.append(name) }
            print((condition ? "ok   " : "FAIL ") + name)
        }

        check("camel-case identifier is English",
              TextTranslator.sourceLanguage(of: "deviceNotEligible")?.languageCode?.identifier == "en")
        check("snake-case identifier is English",
              TextTranslator.sourceLanguage(of: "device_not_eligible")?.languageCode?.identifier == "en")
        check("short ascii word is English, not Vietnamese",
              TextTranslator.sourceLanguage(of: "Bang")?.languageCode?.identifier == "en")
        check("chinese text stays chinese",
              TextTranslator.sourceLanguage(of: "你好世界")?.languageCode?.identifier == "zh")
        check("accented text keeps its detection",
              TextTranslator.sourceLanguage(of: "¿Dónde está la estación?")?.languageCode?.identifier != "en")
        check("single english word qualifies for phonetics",
              TextTranslator.isEnglishWord("deviceNotEligible"))
        check("phrase does not qualify for phonetics",
              !TextTranslator.isEnglishWord("two words"))

        if failures.isEmpty {
            print("text-translator-test: all passed")
        } else {
            print("text-translator-test: \(failures.count) failed")
            exit(1)
        }
    }
}
