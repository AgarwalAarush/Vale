import SwiftUI
import LiltCore

/// Compatibility entry point for older native fixtures; production and fixtures
/// both render the approved compact companion, never the retired workspace.
struct CoachView: View {
    @ObservedObject var model: AppModel
    var chatVisible = true
    var body: some View { CompactCompanionView(model: model, chatVisible: chatVisible) }
}

struct MessageHeading: View {
    let message: Message
    var body: some View {
        HStack(spacing: 6) {
            if ReplySpeaker.showsMark(for: message.role) { Image(systemName: "sparkle").font(.system(size: 8)).foregroundStyle(Theme.accent) }
            Text(message.role == "user" ? "You" : ReplySpeaker.name.localizedCapitalized).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            if ReplyClock.shows(on: message.role) { Text(ReplyClock.label(for: message.date, now: Date())).font(.system(size: 12)).foregroundStyle(Theme.muted) }
        }
    }
}

struct MessageAttachments: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    let records: [AttachmentRecord]
    var body: some View {
        Group {
            if SentFiles.listedInFull || !FileScroll.usesScroll(fileCount: records.count) {
                VStack(alignment: .leading, spacing: 7) { ForEach(records) { record in attachment(record) } }
            } else {
                ScrollView(.horizontal) { HStack(spacing: 7) { ForEach(records) { record in attachment(record) } } }.scrollIndicators(.hidden)
            }
        }.stayInTheCoach()
    }
    @ViewBuilder private func attachment(_ record: AttachmentRecord) -> some View {
        if SentPicture.shows(record), let image = model.fileStore?.image(for: record) {
            Button { model.showFile?(record) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: SentPicture.maxHeight, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(FileName.shown(record.name)).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.buttonStyle(ActionButton()).help("Preview \(record.name)").accessibilityLabel("Preview \(record.name)")
        } else {
            FileChip(record: record, among: records, model: model, removable: SentFile.canRemove(id: record.id, session: session))
        }
    }
}

private struct ReplyTools: View {
    @ObservedObject var model: AppModel
    let message: Message
    @State private var copied = false
    @State private var copyToken = UUID()
    private var reading: Bool { ReplyPlayback.reading(message: message.text, spoken: model.voice.spokenText, speaking: model.voice.speaking) }
    var body: some View {
        HStack(spacing: 16) {
            Button {
                if reading { model.voice.stopSpeaking() } else { model.voice.speak(SpokenReply.text(from: message.text)) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ReplyPlayback.symbol(reading: reading)).symbolRenderingMode(.monochrome).foregroundStyle(reading ? Theme.accent : Theme.muted)
                    Text(ReplyPlayback.label(reading: reading))
                }
            }
                .buttonStyle(ActionButton()).font(.system(size: 12, weight: .medium)).foregroundStyle(reading ? Theme.accent : Theme.muted).help(reading ? "Stop reading" : "Read this reply").accessibilityLabel(reading ? "Stop reading" : "Read this reply")
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ReplyCopy.text(from: message.text), forType: .string)
                let token = UUID(); copyToken = token; copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copyToken == token { copied = false } }
            } label: { Label(copied ? "Copied" : ReplyActions.copy, systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(ActionButton()).font(.system(size: 12, weight: .medium)).foregroundStyle(copied ? Theme.accent : Theme.muted).help("Copy reply").accessibilityLabel(copied ? "Copied" : "Copy reply")
        }.padding(.top, 2)
    }
}

struct MessageText: View {
    let message: Message
    var body: some View {
        if message.showsMarkdown {
            let prepared = ReplyAddress.forDisplay(ReplyLines.forDisplay(message.text))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ReplyCode.segments(prepared).enumerated()), id: \.offset) { _, segment in
                    if segment.code {
                        Text(ReadableLine.display(segment.text)).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if needsLiteral(segment.text) {
                        Text(ReadableLine.display(segment.text))
                    } else {
                        Text(.init(ReadableLine.display(segment.text)))
                    }
                }
            }
        } else {
            Text(QuestionLine.shown(HintRequest.shown(GuideTurn.shown(PointRequest.shown(message.text)))))
        }
    }
    private func needsLiteral(_ text: String) -> Bool {
        let rendered = (try? AttributedString(markdown: text)).map { String($0.characters) } ?? ""
        return AssistantReplyDisplay.needsLiteral(source: text, rendered: rendered)
    }
}

private extension View {
    @ViewBuilder func stayInTheCoach() -> some View {
        if FileRowWidth.staysWithinTheCoach { self.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading) }
        else { self }
    }
    @ViewBuilder func clipExchange(_ clips: Bool) -> some View {
        if clips { self.clipShape(RoundedRectangle(cornerRadius: 10)) } else { self }
    }
}

struct EmptyGreeting: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    var body: some View {
        Text(session.mode == .learn ? "What are we working through?" : "What would you like to work on?")
            .font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.ink).padding(.bottom, 2)
    }
}

/// Passive feedback: Stop response does not cancel an attachment import.
struct AttachmentImportStatus: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            Text(text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).foregroundStyle(Theme.muted)
            .accessibilityElement(children: .ignore).accessibilityLabel(text).accessibilityIdentifier("vale.companion.import-status")
    }
}
