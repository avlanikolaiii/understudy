import Supabase
import SwiftUI

enum Theme {
    static let ink = Color.white
    static let muted = Color(white: 0.62)
    static let rule = Color(white: 0.22)
    static let card = Color(white: 0.11)
    static let ghostLight = Color(red: 0.957, green: 0.773, blue: 0.204)   // #F4C534
    static let warn = Color(red: 0.95, green: 0.64, blue: 0.55)
}

/// A small outlined tag, so simulated or unfinished parts are never mistaken for working ones.
struct StatusTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}

/// Everything that drops down from the notch (or the menu bar icon).
struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var watch: WatchSession
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if watch.isPresented {
                WatchView(session: watch, shortcutLabel: model.shortcutLabel)
            } else {
                Button { watch.start() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle")
                        Text("Watch a new task").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        StatusTag(text: "Simulated")
                    }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
                    .accessibilityHint("Starts a predefined local replay. No account or recording permission needed.")
                switch model.phase {
                case .notConfigured: NotConfiguredView()
                case .loading: ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 30)
                case .signedOut: SignInView(model: model)
                case .signedIn(let email): HomeView(model: model, email: email)
                }
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(model.messageIsError ? Theme.warn : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: 420, alignment: .topLeading)
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.ghostLight).frame(width: 8, height: 8)
                .shadow(color: Theme.ghostLight.opacity(0.8), radius: 5)
                .accessibilityHidden(true)
            Text("Understudy").font(.system(size: 14, weight: .bold))
            Spacer()
            Button { onClose(); model.openSettings?() } label: {
                Image(systemName: "gearshape").font(.system(size: 13))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.muted)
            .accessibilityLabel("Keyboard shortcut settings")
            .help("Change keyboard shortcut · \(model.shortcutLabel)")
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Collapse panel")
                .help(watch.isPlaying ? "Hide panel; simulated replay continues" : "Hide panel")
        }
    }
}

struct NotConfiguredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not connected to a server yet").font(.system(size: 15, weight: .semibold))
            Text("Add your Supabase project URL and anon key to app/config.local.json, then rebuild. The steps are in docs/setup/accounts.md.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SignInView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to keep your skills and connect your apps.")
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            ProviderButton(title: "Continue with Google", symbol: "g.circle.fill") { model.signIn(with: .google) }
                .disabled(model.busy)
            ProviderButton(title: "Continue with Apple", symbol: "apple.logo") { model.signIn(with: .apple) }
                .disabled(model.busy)

            HStack { Rectangle().fill(Theme.rule).frame(height: 1); Text("or").font(.system(size: 11)).foregroundStyle(Theme.muted); Rectangle().fill(Theme.rule).frame(height: 1) }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Email").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    TextField("you@agency.com", text: $model.emailDraft)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .onSubmit { model.sendEmailLink(to: model.emailDraft) }
                        .accessibilityLabel("Email address")
                    Button("Email me a link") { model.sendEmailLink(to: model.emailDraft) }
                        .buttonStyle(.borderedProminent).tint(Theme.ghostLight).foregroundStyle(.black)
                        .disabled(model.busy)
                }
                Text("No password. We'll email you a one-time sign-in link.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct ProviderButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    let email: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(email).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text("\(model.plan.capitalized) plan · \(model.skillCountText)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Sign out") { model.signOut() }.buttonStyle(.link).font(.system(size: 12)).disabled(model.busy)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR SKILLS").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.muted)
                if model.skills.isEmpty {
                    Text("Loading…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                ForEach(model.skills) { skill in
                    HStack(spacing: 10) {
                        Image(systemName: "text.badge.checkmark").foregroundStyle(Theme.ghostLight)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.name).font(.system(size: 13, weight: .semibold))
                            if let client = skill.client { Text(client).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        if skill.isSample { StatusTag(text: "Sample") }
                    }
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ACTIONS").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.muted)
                    Spacer()
                    StatusTag(text: "Next build")
                }
                HStack(spacing: 8) {
                    ActionTile(title: "Rehearse", symbol: "theatermasks")
                    ActionTile(title: "Run now", symbol: "play.fill")
                }
                Text("Rehearsal and runs in this panel are planned for a later build.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT RECEIPTS").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.muted)
                Text("No runs yet.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct ActionTile: View {
    let title: String
    let symbol: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15))
            Text(title).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .foregroundStyle(Theme.muted)
        .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Not available yet")
    }
}
