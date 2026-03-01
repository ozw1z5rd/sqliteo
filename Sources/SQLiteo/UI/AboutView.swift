import SwiftUI

struct AboutView: View {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            VStack(spacing: 8) {
                Text("SQLiteo")
                    .font(.system(size: 32, weight: .bold))

                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("A native SQLite browser for macOS built with Swift.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Link(
                "https://github.com/adamghill/sqliteo",
                destination: URL(string: "https://github.com/adamghill/sqliteo")!
            )
            .font(.body)
            .foregroundColor(.blue)

            Divider()

            Text("Created by Adam Hill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 400)
    }
}

#Preview {
    AboutView()
}
