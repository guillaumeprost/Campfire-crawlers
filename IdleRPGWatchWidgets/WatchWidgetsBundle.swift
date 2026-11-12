import SwiftUI
import WidgetKit

@main
struct WatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HeroComplication()
        HeroLiveComplication()
    }
}
