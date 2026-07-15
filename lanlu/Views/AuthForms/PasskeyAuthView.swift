import SwiftUI

struct PasskeyAuthView: View {
    let serverName: String
    let serverURL: String
    let onSave: (String?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text(String(localized: "passkey_setup_description"))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(String(localized: "save")) {
                onSave(nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle(String(localized: "passkey"))
    }
}
