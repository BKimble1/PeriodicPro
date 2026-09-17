import SwiftUI
import WidgetKit

/// The widget extension's entry point.
@main
struct ElemoraWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickQuestionWidget()
        ElemoraProgressWidget()
    }
}
