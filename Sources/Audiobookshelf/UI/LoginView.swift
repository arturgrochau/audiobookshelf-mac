import ABSCore
import SwiftUI

/// pages/login.vue: logo top-left, a centred card with Username, Password and
/// Submit. The native app also needs the server address, with an optional LAN
/// address that is preferred when reachable.
struct LoginView: View {
  var app = AppModel.shared
  @AppStorage("lastServerURL") private var server = ""
  @AppStorage("lastLocalURL") private var local = ""
  @AppStorage("lastUsername") private var username = ""
  @State private var password = ""
  @State private var processing = false
  @State private var error: String?
  @FocusState private var focus: Field?

  enum Field { case server, local, username, password }

  var body: some View {
    ZStack(alignment: .topLeading) {
      Theme.pageGradient.ignoresSafeArea()
      HStack(spacing: 16) {
        AppLogo().frame(width: 40, height: 40)
        Text("audiobookshelf").font(Theme.sans(20))
      }
      .padding(.leading, 88)
      .padding(.top, 12)
      VStack(spacing: 0) {
        Text(L.s("HeaderLogin")).font(Theme.sans(24, .semibold)).frame(maxWidth: .infinity)
        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.vertical, 16)
        if let error {
          Text(error).font(Theme.sans(16)).foregroundStyle(Theme.error)
            .multilineTextAlignment(.center).padding(.vertical, 8)
        }
        field("Server Address", text: $server, .server, prompt: "https://abs.example.com")
        field("Local Address (optional)", text: $local, .local, prompt: "http://192.168.1.10:13378")
        field(L.s("LabelUsername"), text: $username, .username)
        field(L.s("LabelPassword"), text: $password, .password, secure: true)
        HStack {
          Spacer()
          WebButton(processing ? "Checking..." : L.s("ButtonSubmit"), disabled: processing) {
            submit()
          }
        }
        .padding(.vertical, 12)
      }
      .padding(16)
      .background(Theme.bg)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.05)))
      .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
      .frame(width: 400)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      focus = server.isEmpty ? .server : (username.isEmpty ? .username : .password)
    }
  }

  private func field(_ label: String, text: Binding<String>, _ f: Field, secure: Bool = false,
    prompt: String = "")
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(label.uppercased()).font(Theme.sans(12)).foregroundStyle(Theme.gray300)
      Group {
        if secure {
          SecureField("", text: text)
        } else {
          TextField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.gray500))
        }
      }
      .textFieldStyle(.plain)
      .font(Theme.sans(16))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Theme.primary)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(focus == f ? Theme.gray300 : Theme.gray600))
      .focused($focus, equals: f)
      .disabled(processing)
      .onSubmit(submit)
    }
    .padding(.bottom, 12)
  }

  private func submit() {
    guard !processing else { return }
    let s = server.trimmingCharacters(in: .whitespaces)
    guard let serverURL = URL(string: s.hasPrefix("http") ? s : "https://\(s)"),
      serverURL.host != nil
    else {
      error = "Invalid server address"
      return
    }
    let l = local.trimmingCharacters(in: .whitespaces)
    let localURL = l.isEmpty ? nil : URL(string: l.hasPrefix("http") ? l : "http://\(l)")
    processing = true
    error = nil
    Task {
      defer { processing = false }
      do {
        try await app.login(
          server: serverURL, local: localURL,
          username: username.trimmingCharacters(in: .whitespaces),
          password: password)
        password = ""
      } catch APIError.http(401, let body) {
        error = body.isEmpty ? "Invalid username or password" : body
      } catch APIError.unauthorized {
        error = "Invalid username or password"
      } catch {
        self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }
}
