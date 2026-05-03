import Foundation

@MainActor
protocol TextInsertionClient: AnyObject {
    func insert(_ text: String, action: TextInsertionAction)
}

extension TextInsertionClient {
    func insert(_ text: String) {
        insert(text, action: .paste)
    }
}
