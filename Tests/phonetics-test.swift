import Foundation

// Checks IPA extraction from dictionaryapi.dev responses; the network itself stays in Service.
@main
struct PhoneticsTest {
    static func main() {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures.append(name) }
            print((condition ? "ok   " : "FAIL ") + name)
        }
        func expect(_ actual: String?, expected: String?, _ name: String) {
            let ok = actual == expected
            if !ok { failures.append(name) }
            print((ok ? "ok   " : "FAIL ") + name + ": " + (actual ?? "nil"))
        }

        let sample = #"""
        [
          {
            "word": "hello",
            "phonetic": "həˈləʊ",
            "phonetics": [
              {"text": "həˈləʊ", "audio": "//ssl.gstatic.com/dictionary/static/sounds/20200429/hello--_gb_1.mp3"},
              {"text": "", "audio": ""}
            ],
            "meanings": []
          }
        ]
        """#.data(using: .utf8)!
        expect(PhoneticsEntry.ipa(from: sample), expected: "həˈləʊ", "phonetic field wins")

        let noTopField = #"""
        [
          {
            "word": "apple",
            "phonetics": [
              {"audio": "x.mp3"},
              {"text": "ˈæpl"}
            ],
            "meanings": []
          }
        ]
        """#.data(using: .utf8)!
        expect(PhoneticsEntry.ipa(from: noTopField), expected: "ˈæpl", "first non-empty variant wins")

        let empty = "[]".data(using: .utf8)!
        expect(PhoneticsEntry.ipa(from: empty), expected: nil, "empty entries are nil")

        let garbage = Data("not json".utf8)
        expect(PhoneticsEntry.ipa(from: garbage), expected: nil, "garbage is nil")

        check("single english word", TextTranslator.isEnglishWord("hello"))
        check("phrase is not a word", !TextTranslator.isEnglishWord("hello world"))
        check("chinese is not english", !TextTranslator.isEnglishWord("你好"))
        check("blank is not a word", !TextTranslator.isEnglishWord("  "))

        if failures.isEmpty {
            print("phonetics-test: all passed")
        } else {
            print("phonetics-test: \(failures.count) failed")
            exit(1)
        }
    }
}
