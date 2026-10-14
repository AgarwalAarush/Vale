import SwiftUI
import AVFoundation
import Speech
import LiltCore

struct ContextStrip:View {
    @ObservedObject var model:AppModel
    var body:some View{
        VStack(alignment:.leading,spacing:8){
            HStack(spacing:8){
                Image(systemName:model.context.hasSelection ? "record.circle" : "macwindow").font(.system(size:12)).foregroundStyle(model.context.hasSelection ? Theme.accent : Theme.muted)
                if model.context.hasSelection{
                    Button{model.previewContext()}label:{Text(model.contextName ?? "Selected window").font(.system(size:11)).lineLimit(1)}.buttonStyle(.plain).help("Preview exactly what is shared")
                    Spacer(minLength:4)
                    Toggle("Live",isOn:Binding(get:{model.context.live},set:{if $0{model.context.startLive()}else{model.context.stopLive()}})).toggleStyle(.switch).controlSize(.mini).font(.system(size:10)).disabled(model.paused).help("Refresh this window locally every two seconds; send only when you ask")
                    IconButton(symbol:"xmark",label:"Stop window sharing"){model.stopSharing()}
                }else{
                    Button("Share a window"){model.context.choose()}.buttonStyle(.plain).font(.system(size:11)).disabled(model.paused)
                    Spacer();Text("Optional").font(.system(size:10)).foregroundStyle(Theme.muted)
                }
            }
            if model.context.hasSelection{
                HStack(spacing:5){
                    Text(model.context.live ? "Live locally · sent when you ask" : "Captured when you ask")
                    Spacer(minLength:3)
                    if model.context.capturing{Text("Refreshing…").foregroundStyle(Theme.accent)}
                    else if let date=model.context.lastCapture{Text("\(max(0,Int(Date().timeIntervalSince(date))))s ago").monospacedDigit()}
                }.font(.system(size:11)).foregroundStyle(Theme.faint).monospacedDigit()
            }
        }.padding(.horizontal,8).padding(.vertical,8).background(Theme.raised).clipShape(RoundedRectangle(cornerRadius:8,style:.continuous)).overlay(RoundedRectangle(cornerRadius:8,style:.continuous).strokeBorder(Theme.line,lineWidth:0.5)).padding(.horizontal,16)
    }
}
struct GuideCard:View {
    @ObservedObject var model:AppModel
    let guide:GuideProgress
    var body:some View{
        VStack(alignment:.leading,spacing:8){
            HStack{Text("Step \(guide.index+1) of \(guide.plan.steps.count)").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.accent).monospacedDigit();Spacer();Button("End guide"){model.endGuide()}.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(Theme.muted)}
            Text(guide.current).font(.system(size:13,weight:.medium)).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:12){
                Button("Back"){model.moveGuide(-1)}.buttonStyle(.plain).disabled(guide.index==0)
                Button("Point it out"){model.pointItOut()}.buttonStyle(.plain).disabled(!model.context.hasSelection)
                Spacer()
                if guide.index+1<guide.plan.steps.count{Button("Next step"){model.moveGuide(1)}.buttonStyle(.plain).foregroundStyle(Theme.accent)}
                else{Button("Finish guide"){model.endGuide()}.buttonStyle(.plain).foregroundStyle(Theme.accent)}
            }.font(.system(size:12)).disabled(model.busy || model.paused)
        }.padding(12).background(Theme.raised).clipShape(RoundedRectangle(cornerRadius:8,style:.continuous)).overlay(RoundedRectangle(cornerRadius:8,style:.continuous).strokeBorder(Theme.line,lineWidth:0.5)).padding(.horizontal,16).padding(.top,8)
    }
}
struct VoiceSettings:View {
    @AppStorage("speechLocale") private var locale=""
    @AppStorage("speechVoice") private var voice=""
    @AppStorage("speechRate") private var rate=0.49
    @AppStorage("speechPause") private var pause=2.2
    var body:some View{
        DisclosureGroup("Voice and conversation"){
            VStack(alignment:.leading,spacing:15){
                Picker("Language",selection:$locale){Text("System language").tag("");ForEach(SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted(),id:\.self){id in Text(Locale.current.localizedString(forIdentifier:id) ?? id).tag(id)}}
                Picker("Voice",selection:$voice){Text("System voice").tag("");ForEach(AVSpeechSynthesisVoice.speechVoices().sorted{$0.name<$1.name},id:\.identifier){item in Text("\(item.name) · \(item.language)").tag(item.identifier)}}
                HStack{Text("Speech speed");Slider(value:$rate,in:0.35...0.6);Text(String(format:"%.1f×",rate/0.49)).monospacedDigit().frame(width:34)}
                HStack{Text("Pause before sending");Slider(value:$pause,in:1.2...4,step:0.1);Text(String(format:"%.1fs",pause)).monospacedDigit().frame(width:34)}
                Text("Conversation takes turns: listen, answer, then listen again. Tap the microphone to interrupt; typing stops dictation. Pause or Escape turns conversation and sharing off.").foregroundStyle(Theme.muted).lineSpacing(3)
            }.font(.system(size:12)).padding(.top,14)
        }.font(.system(size:13))
    }
}
