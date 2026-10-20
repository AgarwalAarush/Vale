import SwiftUI

struct ChatGPTAccountSettings: View {
    @ObservedObject var account: ChatGPTAccount
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ChatGPT").font(.system(size: 16, weight: .medium))
            if let active = account.accounts.first(where: { $0.id == account.activeAccountID }) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(active.name).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                    Text(active.label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            Text(account.status).font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if let error = account.error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if account.isSigningIn {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Button("Cancel sign-in") { account.cancelSignIn() }.buttonStyle(QuietButton())
                }
            } else {
                HStack(spacing: 8) {
                    if !account.isSignedIn {
                        Button("Continue with ChatGPT") { account.signIn() }.buttonStyle(QuietButton(filled: true))
                    } else if !account.permitsPlanUsage {
                        Button("Enable ChatGPT plan usage") { account.enablePlanUsage() }.buttonStyle(QuietButton(filled: true))
                    } else {
                        Button("Refresh connection") { account.refreshModels() }.buttonStyle(QuietButton())
                    }
                    if !account.accounts.isEmpty {
                        Button("Add account") { account.addAccount() }.buttonStyle(QuietButton())
                        if account.isSignedIn || account.needsSignOutRetry {
                            Button(account.needsSignOutRetry ? "Retry sign-out" : "Sign out") { account.signOut() }.buttonStyle(QuietButton())
                        }
                    }
                }.disabled(account.isSigningOut)
            }
            if account.accounts.count > 1 {
                Picker("ChatGPT account", selection: Binding(get: { account.activeAccountID ?? "" }, set: { account.selectAccount($0) })) {
                    ForEach(account.accounts) { item in Text("\(item.name) · \(item.label)").tag(item.id) }
                }.font(.system(size: 13)).disabled(account.isSigningIn || account.isSigningOut)
            }
            if account.permitsPlanUsage {
                if account.models.isEmpty {
                    Text("Refresh the connection to load the models available to this account.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else {
                    Picker("Model", selection: Binding(get: { account.selectedModelID }, set: { account.selectModel($0) })) {
                        ForEach(account.models) { model in Text(model.displayName).tag(model.id) }
                    }.font(.system(size: 13)).disabled(account.isSigningOut)
                }
            }
            Text("Your eligible ChatGPT plan covers requests in Vale. OpenAI controls model availability, workspace policy, and app usage limits. Your local Vale chats stay in Vale.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
            Link("Manage ChatGPT usage and access", destination: URL(string: "https://chatgpt.com/settings/usage")!).font(.system(size: 12))
        }.accessibilityElement(children: .contain)
    }
}
