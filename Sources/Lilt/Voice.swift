import AppKit
@preconcurrency import AVFoundation
import Speech
import LiltCore

@MainActor final class VoiceController:NSObject,ObservableObject,AVSpeechSynthesizerDelegate {
    @Published private(set) var listening=false
    @Published private(set) var speaking=false
    @Published private(set) var spokenText:String?
    @Published private(set) var starting=false
    private let engine=AVAudioEngine()
    private let synth=AVSpeechSynthesizer()
    private var recognizer:SFSpeechRecognizer?
    private var activeUtterance:AVSpeechUtterance?
    private var recognition:SFSpeechRecognitionTask?
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var hasTap=false
    private let intake=MicIntake()
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
    var language:String{SpeechLocale.identifier(preferred:UserDefaults.standard.string(forKey:"speechLocale") ?? "",current:Locale.current.identifier)}
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
        let node=engine.inputNode
        engine.prepare()
        let format=node.outputFormat(forBus:0)
        guard MicFormat.canUse(sampleRate:format.sampleRate,channels:Int(format.channelCount)) else{stopListening();failed?("No microphone is available. You can still type.");return}
        intake.allow()
        node.installTap(onBus:0,bufferSize:1024,format:format){[intake] buffer,_ in guard intake.isAccepting else{return};request.append(buffer)};hasTap=true
        do{try engine.start()}catch{stopListening();failed?("Couldn’t start the microphone. You can still type.");return}
        guard RecognitionStart.canListen(engineRunning:engine.isRunning) else{stopListening();failed?("Couldn’t start the microphone. You can still type.");return}
        listening=true
        recognition=recognizer.recognitionTask(with:request){result,error in DispatchQueue.main.async{
            guard self.generation==id,self.listening else{return}
            if let result{
                self.finalText=result.bestTranscription.formattedString;self.partial?(self.finalText);self.silence?.cancel()
                let item=DispatchWorkItem{[weak self]in guard let self,self.generation==id,self.listening else{return};self.finishUtterance()}
                self.silence=item;DispatchQueue.main.asyncAfter(deadline:.now()+self.silenceSeconds,execute:item)
                if result.isFinal{self.finishUtterance()}
            }else if error != nil{self.stopListening();self.failed?("Dictation stopped. Your draft is preserved; send it or try again.")}
        }}
    }
    func finishUtterance(){
        guard listening else{return};let text=finalText.trimmingCharacters(in:.whitespacesAndNewlines);stopListening()
        if !text.isEmpty{finished?(text)}
    }
    func stopListening(){
        generation=UUID();silence?.cancel();silence=nil;starting=false
        intake.stop()
        if engine.isRunning{engine.stop()};if hasTap{engine.inputNode.removeTap(onBus:0);hasTap=false}
        request?.endAudio();recognition?.cancel();recognition=nil;request=nil;recognizer=nil;listening=false
    }
    func speak(_ text:String){
        let spoken=SpokenReply.text(from:text)
        guard !spoken.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        stopListening();stopSpeaking();playbackGeneration=UUID();spokenText=text;speaking=true
        if fixtures{return}
        let utterance=AVSpeechUtterance(string:spoken);let selected=UserDefaults.standard.string(forKey:"speechVoice") ?? ""
        utterance.voice=AVSpeechSynthesisVoice(identifier:selected) ?? AVSpeechSynthesisVoice(language:language)
        guard utterance.voice != nil else{spokenText=nil;speaking=false;return}
        let rate=UserDefaults.standard.double(forKey:"speechRate");utterance.rate=Float(rate==0 ? 0.49 : max(0.35,min(0.6,rate)))
        activeUtterance=utterance;synth.speak(utterance)
    }
    func stopSpeaking(){playbackGeneration=UUID();activeUtterance=nil;spokenText=nil;if !fixtures{synth.stopSpeaking(at:.immediate)};speaking=false}
    func stop(){stopListening();stopSpeaking()}
    nonisolated private func playbackEnded(_ utterance:AVSpeechUtterance,completed:Bool){
        let identity=ObjectIdentifier(utterance)
        DispatchQueue.main.async{[weak self]in
            guard let self,let active=self.activeUtterance,ObjectIdentifier(active)==identity else{return}
            self.activeUtterance=nil;self.spokenText=nil;self.speaking=false
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
