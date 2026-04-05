import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
