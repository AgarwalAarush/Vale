import AppKit
@preconcurrency import AVFoundation
import Speech

@MainActor final class VoiceController:NSObject,ObservableObject,AVSpeechSynthesizerDelegate {
    @Published private(set) var listening=false
    @Published private(set) var speaking=false
    @Published private(set) var starting=false
    private let engine=AVAudioEngine()
    private let synth=AVSpeechSynthesizer()
    private var recognizer:SFSpeechRecognizer?
    private var activeUtterance:AVSpeechUtterance?
    private var recognition:SFSpeechRecognitionTask?
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var hasTap=false
    private var silence:DispatchWorkItem?
    private var finalText=""
    private var generation=UUID()
    private var playbackGeneration=UUID()
    private var fixtures=false
    var fixturePermission=true
    var partial:((String)->Void)?
    var finished:((String)->Void)?
    var failed:((String)->Void)?
    var playbackFinished:(()->Void)?
    var playbackInterrupted:(()->Void)?
    var language:String{let value=UserDefaults.standard.string(forKey:"speechLocale") ?? "";return value.isEmpty ? Locale.current.identifier : value}
    var silenceSeconds:Double{let value=UserDefaults.standard.double(forKey:"speechPause");return value==0 ? 2.2 : max(1.2,min(4,value))}
    override init(){super.init();synth.delegate=self}
    func start(){
        stop();starting=true;let id=UUID();generation=id
        if fixtures{
            starting=false
            guard fixturePermission else{failed?("Microphone access is off. Keep typing, or enable it in System Settings.");return}
            finalText="";listening=true;return
        }
        SFSpeechRecognizer.requestAuthorization{status in DispatchQueue.main.async{
            guard self.generation==id else{return}
            guard status == .authorized else{self.starting=false;self.failed?("Speech access is off. Enable it in System Settings, or keep typing.");return}
            AVCaptureDevice.requestAccess(for:.audio){granted in DispatchQueue.main.async{
                guard self.generation==id else{return}
                guard granted else{self.starting=false;self.failed?("Microphone access is off. Enable it in System Settings, or keep typing.");return}
                self.beginRecognition()
            }}
        }}
    }
    private func beginRecognition(){
        stopListening()
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:language)),recognizer.isAvailable else{failed?("Speech recognition is unavailable. Keep typing or choose another language in Settings.");return}
        self.recognizer=recognizer
        let request=SFSpeechAudioBufferRecognitionRequest();request.shouldReportPartialResults=true;request.requiresOnDeviceRecognition=recognizer.supportsOnDeviceRecognition
        self.request=request;finalText="";let id=UUID();generation=id
        let node=engine.inputNode;let format=node.outputFormat(forBus:0)
        guard format.sampleRate>0,format.channelCount>0 else{failed?("No microphone is available. You can still type.");return}
        node.installTap(onBus:0,bufferSize:1024,format:format){buffer,_ in request.append(buffer)};hasTap=true
        recognition=recognizer.recognitionTask(with:request){result,error in DispatchQueue.main.async{
            guard self.generation==id,self.listening else{return}
            if let result{
                self.finalText=result.bestTranscription.formattedString;self.partial?(self.finalText);self.silence?.cancel()
                let item=DispatchWorkItem{[weak self]in guard let self,self.generation==id,self.listening else{return};self.finishUtterance()}
                self.silence=item;DispatchQueue.main.asyncAfter(deadline:.now()+self.silenceSeconds,execute:item)
                if result.isFinal{self.finishUtterance()}
            }else if error != nil{self.stopListening();self.failed?("Dictation stopped. Your draft is preserved; send it or try again.")}
        }}
        do{engine.prepare();try engine.start();listening=true}catch{stopListening();failed?("Couldn’t start the microphone. You can still type.")}
    }
    func finishUtterance(){
        guard listening else{return};let text=finalText.trimmingCharacters(in:.whitespacesAndNewlines);stopListening()
        if !text.isEmpty{finished?(text)}
    }
    func stopListening(){
        generation=UUID();silence?.cancel();silence=nil;starting=false
        if engine.isRunning{engine.stop()};if hasTap{engine.inputNode.removeTap(onBus:0);hasTap=false}
        request?.endAudio();recognition?.cancel();recognition=nil;request=nil;recognizer=nil;listening=false
    }
    func speak(_ text:String){
        stopListening();stopSpeaking();playbackGeneration=UUID();speaking=true
        if fixtures{return}
        let spoken=text.replacingOccurrences(of:#"\[([^\]]+)\]\([^\)]+\)"#,with:"$1",options:.regularExpression).replacingOccurrences(of:"`",with:"").replacingOccurrences(of:"**",with:"")
        let utterance=AVSpeechUtterance(string:spoken);let selected=UserDefaults.standard.string(forKey:"speechVoice") ?? ""
        utterance.voice=AVSpeechSynthesisVoice(identifier:selected) ?? AVSpeechSynthesisVoice(language:language)
        let rate=UserDefaults.standard.double(forKey:"speechRate");utterance.rate=Float(rate==0 ? 0.49 : max(0.35,min(0.6,rate)))
        activeUtterance=utterance;synth.speak(utterance)
    }
    func stopSpeaking(){playbackGeneration=UUID();activeUtterance=nil;if !fixtures{synth.stopSpeaking(at:.immediate)};speaking=false}
    func stop(){stopListening();stopSpeaking()}
    nonisolated private func playbackEnded(_ utterance:AVSpeechUtterance,completed:Bool){
        let identity=ObjectIdentifier(utterance)
        DispatchQueue.main.async{[weak self]in
            guard let self,let active=self.activeUtterance,ObjectIdentifier(active)==identity else{return}
            self.activeUtterance=nil;self.speaking=false
            if completed{self.playbackFinished?()}else{self.playbackInterrupted?()}
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance){playbackEnded(utterance,completed:true)}
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didCancel utterance:AVSpeechUtterance){playbackEnded(utterance,completed:false)}
    func enableFixtures(){guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else{return};stop();fixtures=true}
    var fixtureRecognitionToken:UUID{generation}
    var fixturePlaybackToken:UUID{playbackGeneration}
    func simulateUtterance(_ text:String,token:UUID){guard fixtures,listening,generation==token else{return};finalText=text;partial?(text);finishUtterance()}
    func simulatePlaybackFinished(token:UUID){guard fixtures,speaking,playbackGeneration==token else{return};speaking=false;playbackFinished?()}
}
