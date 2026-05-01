import Foundation

@MainActor
protocol TextInsertionClient: AnyObject {
    func insert(_ text: String)
}
