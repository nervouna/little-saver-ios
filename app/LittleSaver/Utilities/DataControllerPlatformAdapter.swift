import LittleSaverCore
import WidgetKit

// SwiftUI also declares Transaction; retain the ledger's existing unqualified name.
typealias Transaction = LittleSaverCore.Transaction
typealias Category = LittleSaverCore.Category

extension DataController {
    /// Each executable supplies its own platform side effects to the shared core.
    static let platformShared: DataController = {
        let controller = shared
        controller.reloadWidgets = { WidgetCenter.shared.reloadAllTimelines() }
        return controller
    }()
}
