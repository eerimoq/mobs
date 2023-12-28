import SwiftUI

struct RtmpServerSettingsView: View {
    @EnvironmentObject var model: Model

    private func submitPort(value: String) {
        guard let port = UInt16(value.trim()) else {
            return
        }
        model.database.rtmpServer!.port = port
        model.store()
        model.reloadRtmpServer()
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: Binding(get: {
                    model.database.rtmpServer!.enabled
                }, set: { value in
                    model.database.rtmpServer!.enabled = value
                    model.store()
                    model.reloadRtmpServer()
                }))
            }
            Section {
                let port = model.database.rtmpServer!.port
                NavigationLink(destination: TextEditView(
                    title: String(localized: "Port"),
                    value: String(port),
                    onSubmit: submitPort
                )) {
                    TextItemView(name: String(localized: "Port"), value: String(port))
                }
                HStack {
                    Text("URL")
                    Spacer()
                    Text("rtmp://<your-device-ip>:\(String(port))/camera/")
                    Button(action: {
                        UIPasteboard.general.string = "rtmp://<your-device-ip>:\(String(port))/camera/"
                        model.makeToast(title: "Copied to clipboard")
                    }, label: {
                        Image(systemName: "doc.on.doc")
                    })
                }
            } footer: {
                Text("Normally replace <your-device-ip> with your WiFi IP address.")
            }
            Section {
                List {
                    ForEach(model.database.rtmpServer!.streams) { stream in
                        NavigationLink(destination: RtmpServerStreamSettingsView(stream: stream)) {
                            Text(stream.name)
                        }
                    }
                    .onDelete(perform: { indexes in
                        model.database.rtmpServer!.streams.remove(atOffsets: indexes)
                        model.store()
                        model.reloadRtmpServer()
                    })
                }
                CreateButtonView(action: {
                    model.database.rtmpServer!.streams.append(SettingsRtmpServerStream())
                    model.store()
                    model.objectWillChange.send()
                })
            } header: {
                Text("Streams")
            }
        }
        .navigationTitle("RTMP server")
        .toolbar {
            SettingsToolbar()
        }
    }
}