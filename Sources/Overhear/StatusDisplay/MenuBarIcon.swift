import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var appState: AppState

    var body: some View {
        LiveMark(state: MarkState(status: appState.status, showCancelled: appState.showCancelled))
            .frame(width: 22, height: 22)
    }
}
