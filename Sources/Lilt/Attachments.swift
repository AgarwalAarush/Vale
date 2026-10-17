import AppKit
import PDFKit
import ImageIO
import LiltCore
import UniformTypeIdentifiers

struct FileContext: Sendable {
    var images: [Data] = []
    var text = ""
}

final class AttachmentStore: Sendable {
    let directory: URL
    private let unlink:@Sendable(URL)throws->Void
    static let maxBytes = 25_000_000
    static let textExtensions = Set(["txt","md","markdown","csv","json","jsonl","yaml","yml","xml","html","css","js","jsx","ts","tsx","py","swift","rs","go","java","c","h","cpp","hpp","sql","sh","toml","log","tex","rtf"])
    init(directory: URL,unlink:(@Sendable(URL)throws->Void)?=nil) throws {
        self.unlink=unlink ?? {try FileManager.default.removeItem(at:$0)}
        self.directory=directory.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: self.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }
    func url(for record: AttachmentRecord) -> URL { directory.appendingPathComponent(record.storageName) }
    func importFile(_ url: URL) throws -> AttachmentRecord {
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular, let bytes=attributes[.size] as? NSNumber, bytes.intValue <= Self.maxBytes else { throw AppError("Choose a file under 25 MB.") }
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        return try importData(data,name:url.lastPathComponent,fileExtension:url.pathExtension.lowercased())
    }
    func importData(_ data: Data, name: String, fileExtension ext: String) throws -> AttachmentRecord {
        guard data.count <= Self.maxBytes else { throw AppError("Choose a file under 25 MB.") }
        let kind: AttachmentRecord.Kind
        var stored=data; var detail=""
        if ext == "pdf" {
            guard let pdf=PDFDocument(data:data), !pdf.isLocked, pdf.pageCount > 0 else { throw AppError("This PDF is locked or unreadable.") }
            kind = .pdf; detail="\(pdf.pageCount) \(pdf.pageCount == 1 ? "page" : "pages")"
        } else if let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetType(source) != nil,CGImageSourceGetCount(source)>0 {
            let options: [CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true]
            guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary),let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else { throw AppError("That image couldn’t be read.") }
            kind = .image; stored=png; detail="Image"
        } else if Self.textExtensions.contains(ext) || ext.isEmpty {
            guard var text=String(data:data,encoding:.utf8), !text.contains("\0") else { throw AppError("This file isn’t readable text. Use an image, PDF, or UTF-8 text/code file.") }
            if ext == "rtf", let attributed=NSAttributedString(rtf:data,documentAttributes:nil) { text=attributed.string }
            guard let encoded=text.data(using:.utf8) else { throw AppError("That text couldn’t be read.") }
            kind = .text; stored=encoded; detail=ext.isEmpty ? "Text" : ext.uppercased()
        } else { throw AppError("Supported files: images, PDFs, text, and code. This file type isn’t supported yet.") }
        let record=AttachmentRecord(name:String(name.prefix(180)),kind:kind,byteCount:stored.count,detail:detail)
        try stored.write(to:url(for:record),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url(for:record).path)
        return record
    }
    func remove(_ record: AttachmentRecord)throws {
        let file=url(for:record);guard FileManager.default.fileExists(atPath:file.path) else{return};try unlink(file)
    }
    func image(for record: AttachmentRecord) -> NSImage? { record.kind == .image ? NSImage(contentsOf:url(for:record)) : nil }
    func context(for records: [AttachmentRecord], leadingImages: Int = 0) throws -> FileContext {
        var result=FileContext()
        var textBudget=100_000
        for record in records {
            let file=url(for:record)
            guard FileManager.default.fileExists(atPath:file.path) else { throw AppError("An attachment is unavailable: \(record.name). Remove it or attach it again.") }
            switch record.kind {
            case .image:
                result.images.append(try Data(contentsOf:file))
                result.text += ImageOrder.line(name:record.name, placedBefore:leadingImages, fileImagesSoFar:result.images.count)
            case .text:
                let full=try String(contentsOf:file,encoding:.utf8)
                let take=min(60_000,max(0,textBudget)); let excerpt=String(full.prefix(take)); textBudget-=excerpt.count
                result.text += "\n--- File: \(record.name) ---\n\(excerpt)\n" + (full.count>take ? "[File text truncated; not all content is included.]\n" : "")
            case .pdf:
                guard let pdf=PDFDocument(url:file) else { throw AppError("Couldn’t open \(record.name).") }
                let maximum=min(60_000,max(0,textBudget)); if maximum == 0 {result.text += "\n[PDF \(record.name) is not included because the text context limit was reached.]\n";continue}; var text=""; var pagesRead=0
                for index in 0..<min(pdf.pageCount,300) {
                    guard text.count < maximum else { break }
                    if let page=pdf.page(at:index) { text += "\n[Page \(index+1)]\n" + String((page.string ?? "").prefix(maximum-text.count)); pagesRead=index+1 }
                }
                let extracted = text.replacingOccurrences(of:"[Page ",with:"").filter { $0.isLetter }.count > pagesRead * 2
                if extracted {
                    textBudget-=text.count
                    result.text += "\n--- PDF: \(record.name) (\(pdf.pageCount) pages) ---\n\(text)\n"
                    if pagesRead < pdf.pageCount || text.count >= maximum { result.text += "[PDF text truncated; only the preceding excerpt is available.]\n" }
                } else {
                    result.text += "\nScanned PDF: \(record.name). Only the first \(min(4,pdf.pageCount)) of \(pdf.pageCount) pages follow as images. Do not imply access to later pages.\n"
                    for index in 0..<min(4,pdf.pageCount) {
                        guard let page=pdf.page(at:index) else { continue }
                        let image=page.thumbnail(of:NSSize(width:1200,height:1600),for:.mediaBox)
                        if let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) { result.images.append(png) }
                    }
                }
            }
        }
        guard result.images.count <= 12 else { throw AppError("This chat includes too many visual pages. Remove a file or start a new chat; up to 12 images/pages fit in one request.") }
        return result
    }
}
