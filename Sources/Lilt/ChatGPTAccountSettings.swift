import SwiftUI

struct ChatGPTAccountSettings: View {
    @ObservedObject var account: ChatGPTAccount
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ChatGPT").font(.system(size: 13, weight: .semibold))
                Spacer()
                accountActions
            }
            if let active = account.accounts.first(where: { $0.id == account.activeAccountID }) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(active.name).font(.system(size: 13, weight: .medium))
                        .lineLimit(1).textSelection(.enabled).help(active.name)
                    Spacer(minLength: 4)
                    Text(active.label).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Text(conciseStatus).font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let error = account.error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if account.isSigningIn {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Button("Cancel sign-in") { account.cancelSignIn() }.buttonStyle(.bordered)
                }
            } else if !account.isSignedIn || account.needsIdentityValidation || !account.permitsPlanUsage {
                HStack(spacing: 8) {
                    if !account.isSignedIn {
                        Button("Continue with ChatGPT") { account.signIn() }.buttonStyle(.bordered)
                    } else if account.needsIdentityValidation {
                        Button("Retry connection") { account.refreshModels() }.buttonStyle(.bordered)
                    } else if !account.permitsPlanUsage {
                        Button("Enable plan usage") { account.enablePlanUsage() }.buttonStyle(.bordered)
                    }
                }.disabled(account.isSigningOut)
            }
            if account.accounts.count > 1 {
                Picker("Account", selection: Binding(get: { account.activeAccountID ?? "" }, set: { account.selectAccount($0) })) {
                    ForEach(account.accounts) { item in Text("\(item.name) · \(item.label)").tag(item.id) }
                }.font(.system(size: 13)).disabled(account.isSigningIn || account.isSigningOut)
            }
            if account.permitsPlanUsage {
                if account.models.isEmpty {
                    Text("No models loaded. Refresh the connection.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else {
                    Picker("Model", selection: Binding(get: { account.selectedModelID }, set: { account.selectModel($0) })) {
                        ForEach(account.models) { model in Text(model.displayName).tag(model.id) }
                    }.font(.system(size: 13)).disabled(account.isSigningOut)
                }
            }
            DisclosureGroup("About plan access") {
                Text("Eligible requests use your ChatGPT plan. OpenAI sets model availability, workspace policy and app limits. Your local chats stay in Vale.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }.font(.system(size: 12))
        }.font(.system(size: 13)).controlSize(.small).accessibilityElement(children: .contain)
    }

    private var conciseStatus: String {
        switch account.status {
        case "Connected to ChatGPT. Requests use your ChatGPT plan and app limits.":
            return "Connected · ChatGPT plan"
        case "Continue with ChatGPT to use your eligible plan in Vale.":
            return "Sign in to use your ChatGPT plan."
        case "Continue with ChatGPT to reconnect and send a question.":
            return "Not connected. Sign in to ask a question."
        default:
            // Keep renewal, revocation, workspace and error-specific instructions intact.
            return account.status
        }
    }

    private var accountActions: some View {
        Menu {
            Button("Refresh connection") { account.refreshModels() }
                .disabled(account.isSigningIn || account.isSigningOut || (!account.permitsPlanUsage && !account.needsIdentityValidation))
            if !account.accounts.isEmpty {
                Button("Add account") { account.addAccount() }.disabled(account.isSigningIn || account.isSigningOut)
            }
            if account.isSignedIn || account.needsSignOutRetry {
                Button(account.needsSignOutRetry ? "Retry sign-out" : "Sign out") { account.signOut() }
                    .disabled(account.isSigningIn || account.isSigningOut)
            }
            Divider()
            Link("Manage usage and access…", destination: URL(string: "https://chatgpt.com/settings/usage")!)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 24, height: 22)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("ChatGPT account actions")
            .help("Refresh, add or sign out of an account; manage ChatGPT access")
    }
}
