import SwiftUI
import AVFoundation
import Speech
import LiltCore

struct ContextStrip:View {
    @ObservedObject var model:AppModel
    var body:some View{
        VStack(alignment:.leading,spacing:7){
            HStack(spacing:8){
                Image(systemName:ShareMark.symbol(selected:model.context.hasSelection, live:model.context.live, capturing:model.context.capturing)).font(.system(size:12)).foregroundStyle(model.context.hasSelection ? Theme.accent : Theme.muted)
                if model.context.hasSelection{
                    Button{model.previewContext()}label:{Text(model.contextName ?? "Selected window").font(.system(size:11)).foregroundStyle(Theme.muted).lineLimit(1)}.buttonStyle(.plain).disabled(!HeldPreview.canShow(held: model.context.preview != nil)).help("Preview exactly what is shared")
                    Spacer(minLength:4)
                    Toggle("Live",isOn:Binding(get:{model.context.live},set:{if $0{model.context.startLive()}else{model.context.stopLive()}})).toggleStyle(.switch).controlSize(.mini).font(.system(size:10)).tint(Theme.muted).disabled(model.paused).help("Refresh this window locally every two seconds; send only when you ask")
                    if model.context.capturing { Text("Refreshing…").font(.system(size: 10)).foregroundStyle(Theme.accent) }
                    else if CaptureAge.shows(live: model.context.live, hasCapture: model.context.lastCapture != nil), let date = model.context.lastCapture { Text("\(max(0, Int(Date().timeIntervalSince(date))))s").font(.system(size: 10)).foregroundStyle(Theme.muted).monospacedDigit() }
                    IconButton(symbol:"xmark",label:"Stop window sharing", compact: true, quiet: true){model.stopSharing()}
                }else{
                    Button(ShareControl.title){model.context.choose()}.buttonStyle(.plain).font(.system(size:12, weight: .medium)).foregroundStyle(Theme.muted).disabled(model.paused).help("Choose one window. macOS asks the first time; declining leaves typing available.")
                    Spacer(minLength: 0)
                }
            }
        }.padding(.horizontal,18).padding(.vertical,4)
    }
}
struct GuideCard:View {
    @ObservedObject var model:AppModel
    let guide:GuideProgress
    var body:some View{
        VStack(alignment:.leading,spacing:6){
            HStack{Text("Step \(guide.index+1) of \(guide.plan.steps.count)").font(.system(size:11)).foregroundStyle(Theme.muted);Spacer();Button("End guide"){model.endGuide()}.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Theme.muted)}
            Text(GuideStepText.visible(guide.current)).font(.system(size:12)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:10){
                Button("Back"){model.moveGuide(-1)}.buttonStyle(.plain).foregroundStyle(Theme.muted).disabled(guide.index==0)
                Button("Point it out"){model.pointItOut()}.buttonStyle(.plain).foregroundStyle(Theme.muted).disabled(!model.context.hasSelection)
                Spacer()
                if guide.index+1<guide.plan.steps.count{Button("Next step"){model.moveGuide(1)}.buttonStyle(.plain).foregroundStyle(Theme.accent)}
                else{Button("Finish guide"){model.endGuide()}.buttonStyle(.plain).foregroundStyle(Theme.accent)}
            }.font(.system(size:11)).disabled(model.busy || model.paused)
        }.padding(.vertical, 4).padding(.leading, 12).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1.5).fill(Theme.line).frame(width: 2) }.padding(.horizontal,18).padding(.top,4)
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
