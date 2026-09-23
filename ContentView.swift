import SwiftUI

struct ContentView: View {
    @StateObject private var mesh = BleMeshManager()
    @State private var draft: String = ""
    @State private var nickname: String = UserDefaults.standard.string(forKey: "nickname") ?? ""
    @State private var showNicknamePrompt = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connected peers: \(mesh.peerCount)")
                Spacer()
                Toggle("Relay on", isOn: $mesh.isActive)
                    .labelsHidden()
                Text(mesh.isActive ? "Relay on" : "Relay off")
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(mesh.messages) { message in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(message.senderNickname).bold().font(.caption)
                                    Spacer()
                                    Text(timeString(message.timestamp)).font(.caption2).foregroundColor(.gray)
                                }
                                Text(message.body)
                            }
                            .id(message.id)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: mesh.messages.count) { _ in
                    if let last = mesh.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack {
                TextField("Message nearby devices...", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", action: send)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .onAppear {
            if nickname.isEmpty {
                showNicknamePrompt = true
            } else {
                mesh.localNickname = nickname
            }
        }
        .alert("Pick a display name", isPresented: $showNicknamePrompt) {
            TextField("Name", text: $nickname)
            Button("OK") {
                let finalName = nickname.trimmingCharacters(in: .whitespaces)
                nickname = finalName.isEmpty ? "Anonymous" : finalName
                UserDefaults.standard.set(nickname, forKey: "nickname")
                mesh.localNickname = nickname
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.utf8.count <= 200 else { return } // matches the Android app's cap, see its README
        mesh.sendMessage(text)
        draft = ""
    }

    private func timeString(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
