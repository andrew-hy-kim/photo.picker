import SwiftUI

@main
struct PhotoPickerApp: App {
    @State private var model = ScanModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
