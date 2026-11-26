import SwiftUI

@main
struct TimingCaptureApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel?
    @State private var openError: String?

    init() {
        do {
            _model = State(initialValue: AppModel(store: try CaptureStore(path: CaptureStore.defaultURL())))
        } catch {
            _openError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView(model: model)
                    .task { await model.load() }
                    .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
            } else {
                ContentUnavailableView("Can't open this phone's storage", systemImage: "exclamationmark.triangle",
                                       description: Text("\(openError ?? "") Crossings can't be recorded. See an official."))
            }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        if !model.loaded {
            ProgressView()
        } else if model.pairing == nil || model.pairingAgain {
            PairView(model: model)
        } else {
            CaptureView(model: model)
        }
    }
}
