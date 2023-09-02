import SwiftUI

struct ConnectionsSettingsView: View {
    @ObservedObject var model: Model

    var database: Database {
        get {
            model.settings.database
        }
    }

    var body: some View {
        VStack {
            Form {
                ForEach(0..<model.numberOfConnections, id: \.self) { index in
                    NavigationLink(destination: ConnectionSettingsView(index: index, model: model)) {
                        Toggle(database.connections[index].name, isOn: Binding(get: {
                            database.connections[index].enabled
                        }, set: { value in
                            database.connections[index].enabled = value
                            for cindex in 0..<model.numberOfConnections {
                                if cindex != index {
                                    database.connections[cindex].enabled = false
                                }
                            }
                            model.store()
                            model.numberOfConnections += 0
                            model.reloadConnection()
                        }))
                        .disabled(database.connections[index].enabled)
                    }
                }
                .onDelete(perform: { offsets in
                    database.connections.remove(atOffsets: offsets)
                    model.store()
                    model.numberOfConnections -= 1
                })
                CreateButtonView(action: {
                    database.connections.append(SettingsConnection(name: "My connection"))
                    model.store()
                    model.numberOfConnections += 1
                })
            }
        }
        .navigationTitle("Connections")
    }
}
