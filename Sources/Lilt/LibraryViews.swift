import SwiftUI
import LiltCore

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var query=""
    @State private var deleteID: UUID?
    @State private var renameID: UUID?
    @State private var newTitle=""
    var filtered:[LearningSession]{model.sessions.filter{$0.matches(query)}}
    var body:some View{
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:0){
                HStack(spacing:10){LogoMark(size:26);Text("Vale").font(.system(size:18,weight:.semibold)).tracking(-0.5)}.padding(.horizontal,22).padding(.top,35).padding(.bottom,28)
                Button{model.newSession()}label:{Label("New chat",systemImage:"square.and.pencil").font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.white.opacity(0.065)).clipShape(RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).padding(.horizontal,12)
                Button{model.selectedID=nil;model.settings=false}label:{Label("All chats",systemImage:"rectangle.stack").font(.system(size:12)).foregroundStyle(Theme.muted).padding(.horizontal,12).padding(.vertical,13)}.buttonStyle(.plain).padding(.horizontal,12)
                Text("RECENT").font(.system(size:9,weight:.medium)).tracking(1.2).foregroundStyle(Theme.muted).padding(.horizontal,24).padding(.top,17).padding(.bottom,12)
                ScrollView{
                    VStack(spacing:4){ForEach(model.sessions){chat in
                        Button{model.selectedID=chat.id;model.settings=false}label:{
                            HStack(spacing:9){Image(systemName:chat.mode == .learn ? "lightbulb" : "bubble.left").font(.system(size:12)).foregroundStyle(Theme.muted);Text(chat.title).font(.system(size:12)).lineLimit(1);Spacer(minLength:0)}.padding(.horizontal,12).padding(.vertical,10).background(model.selectedID == chat.id && !model.settings ? .white.opacity(0.065) : .clear).clipShape(RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain).contextMenu{Button("Rename…"){renameID=chat.id;newTitle=chat.title};Button("Export…"){model.export(chat)};Button("Forget chat…",role:.destructive){deleteID=chat.id}}
                    }}.padding(.horizontal,12)
                }.scrollIndicators(.hidden)
                Spacer(minLength:15)
                Button{model.settings=true}label:{Label("Settings",systemImage:"slider.horizontal.3").font(.system(size:12)).foregroundStyle(Theme.muted)}.buttonStyle(.plain).padding(24)
            }.frame(width:194).background(Color.black.opacity(0.12))
            Rectangle().fill(Theme.line).frame(width:1)
            Group{
                if model.settings{SettingsView(model:model)}
                else if let chat=model.selected{SessionDetail(model:model,session:chat,deleteAction:{deleteID=chat.id},renameAction:{renameID=chat.id;newTitle=chat.title})}
                else{home}
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.foregroundStyle(Theme.ink).background(Theme.background).preferredColorScheme(.dark)
        .environment(\.openURL,OpenURLAction{url in ["https","http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded})
        .confirmationDialog("Forget this chat and its uploaded files?",isPresented:Binding(get:{deleteID != nil},set:{if !$0{deleteID=nil}}),titleVisibility:.visible){
            Button("Forget chat",role:.destructive){if let id=deleteID{model.delete(id)};deleteID=nil}
            Button("Cancel",role:.cancel){deleteID=nil}
        }.alert("Rename chat",isPresented:Binding(get:{renameID != nil},set:{if !$0{renameID=nil}})){
            TextField("Chat title",text:$newTitle)
            Button("Cancel",role:.cancel){renameID=nil}
            Button("Save"){if let id=renameID{model.rename(id,to:newTitle)};renameID=nil}
        }
    }
    var home:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:0){
                HStack{Text("Your chats").font(.system(size:29,weight:.medium)).tracking(-0.8);Spacer();Button("New chat"){model.newSession()}.buttonStyle(QuietButton(filled:true))}.padding(.bottom,23)
                HStack(spacing:10){Image(systemName:"magnifyingglass").foregroundStyle(Theme.muted);TextField("Search messages, notes, and files",text:$query).textFieldStyle(.plain).font(.system(size:13))}.padding(12).background(.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Theme.line)).padding(.bottom,27)
                if filtered.isEmpty{
                    VStack(alignment:.leading,spacing:12){
                        Text(query.isEmpty ? "A place to pick up the thread." : "No chats found.").font(.system(size:18,weight:.medium))
                        Text(query.isEmpty ? "Write, plan, debug, compare images, or make sense of a document. Your conversations will be here." : "Try a different phrase or filename.").font(.system(size:13)).foregroundStyle(Theme.muted).lineSpacing(4)
                    }.padding(.top,20)
                }
                ForEach(filtered){chat in
                    Button{model.selectedID=chat.id}label:{
                        HStack(spacing:15){
                            VStack(alignment:.leading,spacing:7){
                                Text(chat.title).font(.system(size:15,weight:.medium)).lineLimit(1)
                                Text(chat.messages.last?.text ?? (chat.pendingAttachments.isEmpty ? "Ready when you are." : "\(chat.pendingAttachments.count) files attached")).font(.system(size:12)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength:20);Text(chat.updated,style:.date).font(.system(size:11)).foregroundStyle(Theme.muted);Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Theme.muted)
                        }.padding(.vertical,18)
                    }.buttonStyle(.plain)
                    Divider().overlay(Theme.line)
                }
                if let error=model.error{
                    VStack(alignment:.leading,spacing:8){
                        Text(error).font(.system(size:12)).foregroundStyle(.orange.opacity(0.9))
                        if model.errorOffersSettings{Button("Open Settings"){model.openSettings()}.buttonStyle(.plain).font(.system(size:12,weight:.medium)).foregroundStyle(Theme.accent)}
                    }.padding(.top,20)
                }
            }.padding(.horizontal,42).padding(.top,56).padding(.bottom,40).frame(maxWidth:.infinity,alignment:.leading)
        }.scrollIndicators(.hidden)
    }
}

struct SessionDetail: View {
    @ObservedObject var model:AppModel
    let session:LearningSession
    let deleteAction:()->Void
    let renameAction:()->Void
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:22){
                HStack(alignment:.top){
                    VStack(alignment:.leading,spacing:9){Text(session.title).font(.system(size:27,weight:.medium)).tracking(-0.7);Text("\(session.mode == .learn ? "Learn" : "Assistant") · \(session.messages.filter{$0.role == "user"}.count) \(session.messages.filter{$0.role == "user"}.count == 1 ? "message" : "messages")").font(.system(size:11)).foregroundStyle(Theme.muted)}
                    Spacer()
                    Menu{Button("Rename…",action:renameAction);Button("Export chat…"){model.export(session)};Button("Forget chat…",role:.destructive,action:deleteAction)}label:{Image(systemName:"ellipsis").frame(width:25,height:25)}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                if let error=model.error{VStack(alignment:.leading,spacing:10){Text(error).font(.system(size:12)).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal:false,vertical:true);if model.errorOffersSettings{Button("Open Settings"){model.openSettings()}.buttonStyle(.plain).font(.system(size:12,weight:.medium)).foregroundStyle(Theme.accent)};if model.deletionToRetry==session.id{Button("Retry Forget"){model.delete(session.id)}.buttonStyle(QuietButton())}}}
                Button(session.id == model.activeID ? "Return to chat" : "Continue chat"){if session.id == model.activeID{model.showCoach?()}else{model.resume(session.id)}}.buttonStyle(QuietButton(filled:true))
                if !session.files.isEmpty{ScrollView(.horizontal){HStack(spacing:8){ForEach(session.files){record in FileChip(record:record,model:model)}}}.scrollIndicators(.hidden)}
                Divider().overlay(Theme.line)
                VStack(alignment:.leading,spacing:10){
                    Text(session.mode == .learn ? "WHAT CLICKED?" : "NOTES").font(.system(size:10,weight:.medium)).tracking(1.1).foregroundStyle(Theme.muted)
                    TextEditor(text:Binding(get:{model.sessions.first{$0.id == session.id}?.takeaway ?? ""},set:{model.setTakeaway($0,for:session.id)})).font(.system(size:14)).scrollContentBackground(.hidden).frame(minHeight:70).padding(9).background(.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Theme.line)).accessibilityLabel("Chat notes")
                }
                if !session.messages.isEmpty{Divider().overlay(Theme.line)}
                ForEach(session.messages){message in
                    VStack(alignment:.leading,spacing:9){
                        Text(message.role == "user" ? "YOU" : "LILT").font(.system(size:10,weight:.medium)).tracking(1).foregroundStyle(Theme.muted)
                        Text(.init(message.text)).font(.system(size:14)).lineSpacing(5).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    }.padding(.vertical,5)
                }
            }.padding(.horizontal,42).padding(.top,54).padding(.bottom,40)
        }.scrollIndicators(.hidden)
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var embeddedInCoach = false
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("model") private var modelName = ""
    @State private var connection = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings").font(.system(size: embeddedInCoach ? 22 : 28, weight: .medium)).tracking(-0.7)
                VStack(alignment: .leading, spacing: 12) {
                    Text("ChatGPT via Codex").font(.system(size: 16, weight: .medium))
                    Text(connection.isEmpty ? (model.provider.executable == nil ? "Codex wasn’t found in ~/.local/bin, Homebrew, the app bundle, or your PATH." : "Uses the sign-in saved by your Codex CLI.") : connection).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Button("Check connection") { checkConnection() }.buttonStyle(QuietButton())
                    Text("To sign in, run codex login in Terminal.").font(.system(size: 11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
                Divider().overlay(Theme.line)
                Toggle("Read typed replies aloud", isOn: $model.readAloud).toggleStyle(.switch).font(.system(size: 13))
                Text("The microphone starts when you choose Talk or Conversation. Conversation listens again after each answer; Pause or Escape stops it. Apple’s on-device speech recognition is used when available.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                VoiceSettings()
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your context, your choice").font(.system(size: 16, weight: .medium))
                    Text("Your messages, uploaded files, and the window you explicitly share are sent when you ask. Live refresh keeps only the latest selected-window preview in memory, every two seconds. Images are sent when you ask, not on every refresh. A selected window includes whichever page is visible inside it.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                    Text("Chats and uploaded files are retained locally. Forget removes a chat and its files. Captured screens and microphone recordings are not saved to chat history.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                }
                VStack(alignment:.leading,spacing:12){
                    Text("Updates").font(.system(size:16,weight:.medium))
                    Text(model.updates.status).font(.system(size:12)).foregroundStyle(Theme.muted).lineSpacing(4)
                    Button("Check for Updates…"){model.updates.check()}.buttonStyle(QuietButton()).disabled(!model.updates.canCheck)
                }
                Divider().overlay(Theme.line)
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Codex executable").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        TextField("Auto-detect", text: $codexPath).textFieldStyle(.roundedBorder).font(.system(size: 12))
                        Text("Model").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        TextField("Codex default", text: $modelName).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    }.padding(.top, 15)
                }.font(.system(size: 12))
                Text("Open coach anywhere: Control–Option–Space").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("Vale 1.2.2 · Your companion, wherever you work").font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.7))
            }.padding(.horizontal, embeddedInCoach ? 18 : 42).padding(.top, embeddedInCoach ? 8 : 54).padding(.bottom, embeddedInCoach ? 20 : 40)
        }.scrollIndicators(.hidden)
    }
    func checkConnection() {
        guard let path = model.provider.executable else { connection = "Codex wasn’t found. Choose its path below."; return }
        connection = "Checking…"
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = ["login", "status"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        process.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { connection = process.terminationStatus == 0 ? (text.contains("ChatGPT") ? "Signed in with ChatGPT." : "Codex is signed in.") : "Not signed in. Run codex login in Terminal." }
        }
        do { try process.run() } catch { connection = "Couldn’t launch Codex. Check the executable path." }
    }
}
