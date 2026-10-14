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
                HStack(spacing:8){LogoMark(size:24);Text("Vale").font(.system(size:15,weight:.semibold)).tracking(-0.3)}.padding(.horizontal,16).padding(.top,16).padding(.bottom,16)
                NavRow(title:"New chat",symbol:"square.and.pencil",selected:false){model.newSession()}.padding(.horizontal,8)
                NavRow(title:"All chats",symbol:"rectangle.stack",selected:model.selectedID==nil && !model.settings){model.selectedID=nil;model.settings=false}.padding(.horizontal,8).padding(.top,4)
                Text("Recent").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.faint).padding(.horizontal,16).padding(.top,16).padding(.bottom,8)
                ScrollView{
                    VStack(spacing:2){ForEach(model.sessions){chat in
                        NavRow(title:chat.title,symbol:chat.mode == .learn ? "lightbulb" : "bubble.left",selected:model.selectedID==chat.id && !model.settings){model.selectedID=chat.id;model.settings=false}
                            .contextMenu{Button("Rename…"){renameID=chat.id;newTitle=chat.title};Button("Export…"){model.export(chat)};Button("Forget chat…",role:.destructive){deleteID=chat.id}}
                    }}.padding(.horizontal,8)
                }.scrollIndicators(.hidden)
                Spacer(minLength:8)
                NavRow(title:"Settings",symbol:"slider.horizontal.3",selected:model.settings){model.settings=true}.padding(8)
            }.frame(width:208).background(Color.white.opacity(0.02))
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
                HStack{Text("Your chats").font(.system(size:20,weight:.semibold)).tracking(-0.4);Spacer();Button("New chat"){model.newSession()}.buttonStyle(QuietButton(filled:true))}.padding(.bottom,16)
                HStack(spacing:8){Image(systemName:"magnifyingglass").font(.system(size:12)).foregroundStyle(Theme.faint);TextField("Search messages, notes, and files",text:$query).textFieldStyle(.plain).font(.system(size:13))}.padding(.horizontal,8).padding(.vertical,8).background(Theme.raised).clipShape(RoundedRectangle(cornerRadius:8,style:.continuous)).overlay(RoundedRectangle(cornerRadius:8,style:.continuous).strokeBorder(Theme.line,lineWidth:0.5)).padding(.bottom,16)
                if filtered.isEmpty{
                    VStack(alignment:.leading,spacing:8){
                        Text(query.isEmpty ? "A place to pick up the thread." : "No chats found.").font(.system(size:15,weight:.semibold)).tracking(-0.2)
                        Text(query.isEmpty ? "Write, plan, debug, compare images, or make sense of a document. Your conversations will be here." : "Try a different phrase or filename.").font(.system(size:13)).foregroundStyle(Theme.muted).lineSpacing(3).frame(maxWidth:520,alignment:.leading)
                    }.padding(.top,16)
                }
                ForEach(filtered){chat in
                    ChatRow(chat:chat){model.selectedID=chat.id}
                    Rectangle().fill(Theme.line).frame(height:0.5)
                }
                if let error=model.error{Text(error).font(.system(size:12)).foregroundStyle(Theme.danger).padding(.top,16)}
            }.padding(.horizontal,32).padding(.top,32).padding(.bottom,32).frame(maxWidth:.infinity,alignment:.leading)
        }.scrollIndicators(.hidden)
    }
}

struct SessionDetail: View {
    @ObservedObject var model:AppModel
    let session:LearningSession
    let deleteAction:()->Void
    let renameAction:()->Void
    @State private var menu=false
    @State private var highlight=0
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:16){
                HStack(alignment:.top){
                    VStack(alignment:.leading,spacing:4){Text(session.title).font(.system(size:20,weight:.semibold)).tracking(-0.4);Text(sessionMeta).font(.system(size:12)).foregroundStyle(Theme.muted).monospacedDigit()}
                    Spacer()
                    sessionMenu
                }.zIndex(1)
                if let error=model.error{VStack(alignment:.leading,spacing:8){Text(error).font(.system(size:12)).foregroundStyle(Theme.danger).textSelection(.enabled).fixedSize(horizontal:false,vertical:true);if model.deletionToRetry==session.id{Button("Retry Forget"){model.delete(session.id)}.buttonStyle(QuietButton())}}}
                Button(session.id == model.activeID ? "Return to chat" : "Continue chat"){if session.id == model.activeID{model.showCoach?()}else{model.resume(session.id)}}.buttonStyle(QuietButton(filled:true))
                if !session.files.isEmpty{ScrollView(.horizontal){HStack(spacing:8){ForEach(session.files){record in FileChip(record:record,model:model)}}}.scrollIndicators(.hidden)}
                Divider().overlay(Theme.line)
                VStack(alignment:.leading,spacing:8){
                    Text(session.mode == .learn ? "What clicked" : "Notes").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.muted)
                    TextEditor(text:Binding(get:{model.sessions.first{$0.id == session.id}?.takeaway ?? ""},set:{model.setTakeaway($0,for:session.id)})).font(.system(size:13)).scrollContentBackground(.hidden).frame(minHeight:72).padding(8).background(Theme.raised).clipShape(RoundedRectangle(cornerRadius:8,style:.continuous)).overlay(RoundedRectangle(cornerRadius:8,style:.continuous).strokeBorder(Theme.line,lineWidth:0.5)).accessibilityLabel("Chat notes")
                }
                if !session.messages.isEmpty{Rectangle().fill(Theme.line).frame(height:0.5)}
                ForEach(session.messages){message in
                    VStack(alignment:.leading,spacing:4){
                        Text(message.role == "user" ? "You" : "Lilt").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.faint)
                        Text(.init(message.text)).font(.system(size:13)).lineSpacing(3).textSelection(.enabled).frame(maxWidth:560,alignment:.leading)
                    }.padding(.vertical,4)
                }
            }.padding(.horizontal,32).padding(.top,32).padding(.bottom,32)
        }.scrollIndicators(.hidden)
    }
    private var sessionMeta:String{
        let count=session.messages.filter{$0.role=="user"}.count
        return "\(session.mode == .learn ? "Learn" : "Assistant") · \(count) \(count == 1 ? "message" : "messages")"
    }
    private var sessionMenu:some View{
        IconButton(symbol:"ellipsis",label:"Chat actions",side:24){menu.toggle()}
            .overlay(alignment:.topTrailing){
                if menu{
                    CommandList(sections:[[
                        CommandEntry(id:"rename",title:"Rename",symbol:"pencil",action:renameAction),
                        CommandEntry(id:"export",title:"Export chat",symbol:"square.and.arrow.up",action:{model.export(session)}),
                        CommandEntry(id:"forget",title:"Forget chat",symbol:"trash",destructive:true,action:deleteAction)
                    ]],highlight:$highlight){item in menu=false; item.action()}
                    .frame(width:200)
                    .background(RoundedRectangle(cornerRadius:8,style:.continuous).fill(Theme.background).overlay(RoundedRectangle(cornerRadius:8,style:.continuous).strokeBorder(Theme.line,lineWidth:0.5)))
                    .offset(y:28)
                }
            }
    }
}
private struct NavRow:View{
    var title:String
    var symbol:String
    var selected:Bool
    var action:()->Void
    @State private var hover=false
    var body:some View{
        Button(action:action){
            HStack(spacing:8){
                Image(systemName:symbol).font(.system(size:12)).frame(width:16)
                Text(title).font(.system(size:13,weight:selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength:0)
            }
            .padding(.horizontal,8).padding(.vertical,8)
            .foregroundStyle(selected || hover ? Theme.ink : Theme.muted)
            .background(RoundedRectangle(cornerRadius:8,style:.continuous).fill(Color.white.opacity(selected ? 0.08 : hover ? 0.04 : 0)))
        }.buttonStyle(.plain).onHover{hover=$0}
    }
}
private struct ChatRow:View{
    let chat:LearningSession
    var action:()->Void
    @State private var hover=false
    var body:some View{
        Button(action:action){
            HStack(spacing:16){
                VStack(alignment:.leading,spacing:4){
                    Text(chat.title).font(.system(size:13,weight:.medium)).lineLimit(1)
                    Text(chat.messages.last?.text ?? (chat.pendingAttachments.isEmpty ? "Ready when you are." : "\(chat.pendingAttachments.count) files attached")).font(.system(size:12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength:16)
                Text(chat.updated,style:.date).font(.system(size:11)).foregroundStyle(Theme.faint).monospacedDigit()
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Theme.faint)
            }.padding(.vertical,12).padding(.horizontal,8)
            .background(RoundedRectangle(cornerRadius:8,style:.continuous).fill(Color.white.opacity(hover ? 0.04 : 0)))
        }.buttonStyle(.plain).onHover{hover=$0}
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("model") private var modelName = ""
    @State private var connection = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                VStack(alignment: .leading, spacing: 12) {
                    Text("ChatGPT via Codex").font(.system(size: 16, weight: .medium))
                    Text(connection.isEmpty ? (model.provider.executable == nil ? "Codex wasn’t found on this Mac." : "Uses the sign-in saved by your Codex CLI.") : connection).font(.system(size: 12)).foregroundStyle(Theme.muted)
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
                    VStack(alignment: .leading, spacing: 8) {
                        LineField(title: "Codex executable", prompt: "Auto-detect", text: $codexPath)
                        LineField(title: "Model", prompt: "Codex default", text: $modelName)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
                Text("Open coach anywhere: Control–Option–Space").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("Vale 1.2.2 · Your companion, wherever you work").font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.7))
            }.padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 32)
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
