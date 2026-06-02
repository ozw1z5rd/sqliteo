import SwiftUI

struct AboutView: View {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "local development"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "beta"

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

            VStack(spacing: 4) {
                Text("A native MacOS SQLite browser")
                    .multilineTextAlignment(.center)
                Text("built with Swift.")
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            Divider()

            Link(
                "https://github.com/adamghill/sqliteo",
                destination: URL(string: "https://github.com/adamghill/sqliteo")!
            )
            .font(.body)
            .foregroundColor(.blue)



            Text("Original work by Adam Hill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            
            

            
            Link(
                "https://github.com/ozw1z5rd/sqliteo",
                destination: URL(string: "https://github.com/ozw1z5rd/sqliteo")!
            )
            .font(.body)
            .foregroundColor(.blue)
            
            Text("MacOS 13 version by Alessio Palma")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("SVG icon by Shiraz Jamal")
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
