import SwiftUI
import AppKit
import LiltCore

struct CompactCompanionMessage: View {
    @ObservedObject var model: AppModel
    let message: Message
    @State private var copied = false
    @State private var copyToken = UUID()
    private var reading: Bool { ReplyPlayback.reading(message: message.text, spoken: model.voice.spokenText, speaking: model.voice.speaking) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.text.isEmpty {
                MessageText(message: message)
                    .font(.system(size: 13)).lineSpacing(message.role == "user" ? 2 : 4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(message.role == "user" ? Theme.muted : Theme.ink)
                    .padding(message.role == "user" ? 10 : 0)
                    .background(message.role == "user" ? Theme.fill.opacity(0.7) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            if !message.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(message.attachments) { record in
                            Button { model.showFile?(record) } label: {
                                Label(record.name, systemImage: record.kind == .image ? "photo" : "doc")
                                    .font(.system(size: 11)).lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(Theme.fill.opacity(0.65)).clipShape(Capsule())
                            }.buttonStyle(ActionButton()).help("Preview " + record.name)
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: 29)
            }
            if message.replyStopped { Text(StoppedReply.label).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            if message.answerFailed && !model.busy { Text(FailedAnswer.label).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            if message.highlightUnavailable { Label("Highlight unavailable", systemImage: "eye.slash").font(.system(size: 11)).foregroundStyle(Theme.muted) }
            if StaleWindowAnswer.applies(to: message) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(StaleWindowAnswer.notice)
                    if message.id == model.active?.messages.last?.id { Button("Refresh answer") { model.refreshAnswer() }.buttonStyle(ActionButton()).foregroundStyle(Theme.accent) }
                }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if message.role == "assistant" {
                HStack(spacing: 9) {
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ReplyCopy.text(from: message.text), forType: .string)
                        let token = UUID(); copyToken = token; copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copyToken == token { copied = false } }
                    } label: { Label(copied ? "Copied" : "Copy reply", systemImage: copied ? "checkmark" : "doc.on.doc").labelStyle(.iconOnly).frame(width: 24, height: 24) }
                        .buttonStyle(ActionButton()).help(copied ? "Copied" : "Copy reply")
                    Button {
                        if reading { model.voice.stopSpeaking() } else { model.voice.speak(SpokenReply.text(from: message.text)) }
                    } label: { Label(reading ? "Stop reading" : "Read reply aloud", systemImage: reading ? "stop.fill" : "speaker.wave.2").labelStyle(.iconOnly).frame(width: 24, height: 24) }
                        .buttonStyle(ActionButton()).help(reading ? "Stop reading" : "Read reply aloud")
                }.font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
