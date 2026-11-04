import Foundation

@main
struct WebToolLoadPolicyTests {
    static func expect(_ actual: WebToolLoadPolicy?, _ expected: WebToolLoadPolicy?, _ message: String) {
        guard actual == expected else {
            print("FAIL: \(message) — got \(String(describing: actual)), want \(String(describing: expected))")
            exit(1)
        }
    }

    static func main() {
        expect(
            WebToolLoadPolicy.resolve(hasLoadedPage: false, refreshPending: false), .initial,
            "the first panel open loads the page")
        expect(
            WebToolLoadPolicy.resolve(hasLoadedPage: true, refreshPending: false), nil,
            "an unchanged cached page opens immediately")
        expect(
            WebToolLoadPolicy.resolve(hasLoadedPage: true, refreshPending: true), .refresh,
            "a detected update refreshes on the next explicit open")
        expect(
            WebToolLoadPolicy.resolve(hasLoadedPage: false, refreshPending: true), .initial,
            "a first load is never a refresh")
        print("4 passed, 0 failed")
    }
}
