import SwiftUI
import PDFKit
import LiltCore

struct FileChip: View {
    let record: AttachmentRecord
    @ObservedObject var model: AppModel
    var removable = false
    var body: some View {
        HStack(spacing:8) {
            Button {model.showFile?(record)} label:{
                HStack(spacing:8){
                    if let image=model.fileStore?.image(for:record){Image(nsImage:image).resizable().scaledToFill().frame(width:28,height:28).clipShape(RoundedRectangle(cornerRadius:5))}
                    else{Image(systemName:record.kind == .pdf ? "doc.richtext" : "doc.text").font(.system(size:16)).foregroundStyle(Theme.accent).frame(width:28,height:28)}
                    VStack(alignment:.leading,spacing:3){Text(record.name).font(.system(size:11,weight:.medium)).lineLimit(1);Text(record.detail).font(.system(size:9)).foregroundStyle(Theme.muted).lineLimit(1)}
                }
            }.buttonStyle(.plain).help("Preview \(record.name)")
            if removable{Button{model.removeFile(record)}label:{Image(systemName:"xmark").font(.system(size:8)).frame(width:18,height:22)}.buttonStyle(.plain).foregroundStyle(Theme.muted).help("Remove \(record.name)")}
        }.padding(8).frame(maxWidth:210,alignment:.leading).background(.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Theme.line,lineWidth:0.6))
    }
}
struct PDFPreview: View {
    let url:URL
    @State private var document:PDFDocument?
    @State private var pageIndex=0
    @State private var image:NSImage?
    var body:some View {
        VStack(spacing:0){
            HStack(spacing:14){
                IconButton(symbol:"chevron.left",label:"Previous page"){pageIndex-=1;render()}.disabled(pageIndex==0)
                Text("Page \(pageIndex+1) of \(document?.pageCount ?? 0)").font(.system(size:12)).foregroundStyle(Theme.muted).monospacedDigit()
                IconButton(symbol:"chevron.right",label:"Next page"){pageIndex+=1;render()}.disabled(pageIndex+1 >= (document?.pageCount ?? 0))
                Spacer()
                Button("Copy page text"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(document?.page(at:pageIndex)?.string ?? "",forType:.string)}.buttonStyle(QuietButton()).disabled(document?.page(at:pageIndex)?.string?.isEmpty != false)
            }.padding(.horizontal,18).padding(.vertical,9)
            Divider().overlay(Theme.line)
            if let image{Image(nsImage:image).resizable().scaledToFit().padding(20).frame(maxWidth:.infinity,maxHeight:.infinity)}
            else{Text("This page couldn’t be previewed.").font(.system(size:13)).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.onAppear{document=PDFDocument(url:url);render()}
    }
    private func render(){image=document?.page(at:pageIndex)?.thumbnail(of:NSSize(width:1600,height:2000),for:.mediaBox)}
}
struct FilePreviewView: View {
    let record:AttachmentRecord
    let store:AttachmentStore
    var body:some View{
        Group{
            if record.kind == .pdf{PDFPreview(url:store.url(for:record))}
            else if let image=store.image(for:record){Image(nsImage:image).resizable().scaledToFit().padding(18).frame(maxWidth:.infinity,maxHeight:.infinity)}
            else{ScrollView{Text(textPreview).font(.system(size:13,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(24)}}
        }.background(Theme.background).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
    private var textPreview:String{
        guard let text=try? String(contentsOf:store.url(for:record),encoding:.utf8) else{return "File unavailable."}
        return String(text.prefix(100_000)) + (text.count>100_000 ? "\n\n[Preview limited to the first 100,000 characters.]" : "")
    }
}
