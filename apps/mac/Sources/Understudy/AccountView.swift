import SwiftUI

/// Sign-in and account status, in the main window. The notch never asks for sign-in.
struct AccountView: View {
    @ObservedObject var auth: AppModel
    @ObservedObject var library: SkillLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Account").font(.largeTitle.weight(.bold))
                Text("Sign in to keep your skills and receipts in your account and, later, connect your apps.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            switch auth.phase {
            case .notConfigured: notConfigured
            case .loading: ProgressView().controlSize(.small)
            case .signedOut: signIn
            case .signedIn(let email): signedIn(email)
            }
            if let message = auth.message {
                Text(message).font(.callout)
                    .foregroundStyle(auth.messageIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var notConfigured: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Account sign-in isn't set up on this Mac yet", systemImage: "icloud.slash").font(.headline)
                Text("The Understudy server hasn't been connected to this build. Until it is, you're in **Sample mode**: skills and receipts are saved on this Mac only.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Setup steps: docs/setup/accounts.md in the project.")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { auth.signIn(with: .google) } label: {
                Label("Continue with Google", systemImage: "g.circle.fill").frame(maxWidth: 320, alignment: .leading)
            }.controlSize(.large).disabled(auth.busy)
            Button { auth.signIn(with: .apple) } label: {
                Label("Continue with Apple", systemImage: "apple.logo").frame(maxWidth: 320, alignment: .leading)
            }.controlSize(.large).disabled(auth.busy)
            Divider().frame(maxWidth: 360)
            Text("Or get a sign-in link by email").font(.system(size: 13, weight: .semibold))
            HStack {
                TextField("you@agency.com", text: $auth.emailDraft)
                    .textFieldStyle(.roundedBorder).textContentType(.emailAddress)
                    .onSubmit { auth.sendEmailLink(to: auth.emailDraft) }
                    .frame(maxWidth: 260)
                    .accessibilityLabel("Email address")
                Button("Email me a link") { auth.sendEmailLink(to: auth.emailDraft) }
                    .buttonStyle(.borderedProminent).disabled(auth.busy)
            }
            Text("No password. Open the link on this Mac.").font(.caption).foregroundStyle(.secondary)
            Text("Until you sign in, you're in Sample mode and everything stays on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func signedIn(_ email: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email).font(.headline).textSelection(.enabled)
                        Text("\(library.plan.capitalized) plan · \(library.skillCountText)").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign Out") { auth.signOut() }.disabled(auth.busy)
                }
                if library.loading { ProgressView("Loading your skills…").controlSize(.small) }
                Text("Your skills and receipts are saved to your account. Connectors aren't available yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
}
