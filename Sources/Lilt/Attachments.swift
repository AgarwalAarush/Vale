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
    static let maxBytes = AttachmentFileKind.maxBytes
    static let textExtensions = SourceFile.extensions.union(TextKind.extensions)
    init(directory: URL,unlink:(@Sendable(URL)throws->Void)?=nil) throws {
        self.unlink=unlink ?? {try FileManager.default.removeItem(at:$0)}
        self.directory=directory.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: self.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }
    func url(for record: AttachmentRecord) -> URL { directory.appendingPathComponent(record.storageName) }
    static func readablePDF(_ pdf: PDFDocument) -> PDFDocument? {
        let wasLocked=pdf.isLocked
        let unlockSucceeded=wasLocked && pdf.unlock(withPassword:"")
        guard PdfAccess.shouldAccept(wasLocked:wasLocked, unlockSucceeded:unlockSucceeded), pdf.pageCount>0 else { return nil }
        return pdf
    }
    func importFile(_ url: URL) throws -> AttachmentRecord {
        try importDroppedFile(url,extraRoom:0)[0]
    }
    private func resolvedFile(_ url:URL)->URL{
        let linked=url.resolvingSymlinksInPath()
        let isAlias=(try? linked.resourceValues(forKeys:[.isAliasFileKey]).isAliasFile)==true
        let resolved=isAlias ? try? URL(resolvingAliasFileAt:linked,options:[.withoutUI,.withoutMounting]) : nil
        return AliasFile.urlToRead(original:linked,resolved:resolved,isAlias:isAlias).resolvingSymlinksInPath()
    }
    func importDroppedFile(_ url:URL,extraRoom:Int)throws->[AttachmentRecord]{
        let target=resolvedFile(url)
        let attributes=try FileManager.default.attributesOfItem(atPath:target.path)
        if let refusal=AttachmentFileKind.refusal(isRegularFile:(attributes[.type] as? FileAttributeType) == .typeRegular,byteCount:(attributes[.size] as? NSNumber)?.intValue){throw AppError(refusal)}
        let data=try Data(contentsOf:target,options:.mappedIfSafe)
        let ext=target.pathExtension.lowercased()
        if ["tif","tiff"].contains(ext),let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetCount(source)>1{
            let pages=CGImageSourceGetCount(source)
            let extras=ImagePages.extraPages(pageCount:pages,extraRoom:extraRoom)
            var kept:[AttachmentRecord]=[]
            do{
                for index in 0..<(1+extras){
                    guard let png=imagePNG(source,index:index) else{throw AppError("That image couldn’t be read.")}
                    let base=target.deletingPathExtension().lastPathComponent
                    let name=extras==0 ? target.lastPathComponent : "\(base) \(index+1).\(ext)"
                    kept.append(try save(png,name:name,kind:.image,detail:"Page \(index+1) of \(pages)"))
                }
                return kept
            }catch{
                for record in kept{try? remove(record)}
                throw error
            }
        }
        return [try importData(data,name:target.lastPathComponent,fileExtension:ext)]
    }
    func importData(_ data: Data, name: String, fileExtension ext: String) throws -> AttachmentRecord {
        if let refusal=AttachmentFileKind.refusal(isRegularFile:true,byteCount:data.count){throw AppError(refusal)}
        let kind: AttachmentRecord.Kind
        var stored=data; var detail=""
        var laterPages:Data?
        if FileSignature.treatAsPDF(fileExtension:ext,data:data,isTextExtension:Self.textExtensions.contains(ext)) {
            let pages=try onMain{
                guard let opened=PDFDocument(data:data),let pdf=Self.readablePDF(opened) else{throw AppError("This PDF is locked or unreadable.")}
                return pdf.pageCount
            }
            kind = .pdf; detail=PdfChip.detail(pages:pages)
        } else if ext == "rtf" {
            let plain=onMain{NSAttributedString(rtf:data,documentAttributes:nil)?.string}
            guard let text=RichText.textToStore(plain),let encoded=text.data(using:.utf8) else{throw AppError("This rich-text file couldn’t be read.")}
            kind = .text;stored=encoded;detail="RTF"
        } else if WordFile.isDocument(ext) {
            let options:[NSAttributedString.DocumentReadingOptionKey:Any]=[.documentType:NSAttributedString.DocumentType.officeOpenXML]
            let plain=onMain{try? NSAttributedString(data:data,options:options,documentAttributes:nil).string}
            guard let text=plain.flatMap(WordFile.text),let encoded=text.data(using:.utf8) else{throw AppError("This Word document has no readable text.")}
            kind = .text;stored=encoded;detail="DOCX"
        } else if !TextFileRoute.readBeforeImage(fileExtension:ext,isTextExtension:Self.textExtensions.contains(ext)),let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetType(source) != nil,CGImageSourceGetCount(source)>0 {
            guard let png=imagePNG(source,index:0) else { throw AppError("That image couldn’t be read.") }
            kind = .image; stored=png; detail="Image"
            if CGImageSourceGetCount(source)>1{laterPages=data}
        } else if Self.textExtensions.contains(ext) || ext.isEmpty {
            guard let text=TextFile.decode(data),SourceFile.isReadable(text) else { throw AppError("This file isn’t readable text. Use an image, PDF, or UTF-8 text/code file.") }
            guard let encoded=text.data(using:.utf8) else { throw AppError("That text couldn’t be read.") }
            kind = .text; stored=encoded; detail=ext.isEmpty ? "Text" : ext.uppercased()
        } else { throw AppError("Supported files: images, PDFs, text, and code. This file type isn’t supported yet.") }
        let record=try save(stored,name:name,kind:kind,detail:detail)
        if let laterPages{
            let pages=pagesURL(for:record)
            do{
                try laterPages.write(to:pages,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:pages.path)
            }catch{
                // Neither file is referenced by a chat until this import returns successfully.
                try? FileManager.default.removeItem(at:pages)
                try? FileManager.default.removeItem(at:url(for:record))
                throw error
            }
        }
        return record
    }
    private func save(_ data:Data,name:String,kind:AttachmentRecord.Kind,detail:String)throws->AttachmentRecord{
        let record=AttachmentRecord(name:String(name.prefix(180)),kind:kind,byteCount:data.count,detail:detail)
        do{
            try data.write(to:url(for:record),options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url(for:record).path)
        }catch{
            try? FileManager.default.removeItem(at:url(for:record))
            throw error
        }
        return record
    }
    private func imagePNG(_ source:CGImageSource,index:Int)->Data?{
        let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true]
        if let preview=CGImageSourceCreateThumbnailAtIndex(source,index,options as CFDictionary),let png=NSBitmapImageRep(cgImage:preview).representation(using:.png,properties:[:]){return png}
        return CGImageSourceCreateImageAtIndex(source,index,nil).flatMap{NSBitmapImageRep(cgImage:$0).representation(using:.png,properties:[:])}
    }
    func remove(_ record: AttachmentRecord)throws {
        let pages=pagesURL(for:record)
        if FileManager.default.fileExists(atPath:pages.path){try unlink(pages)}
        let file=url(for:record);guard FileManager.default.fileExists(atPath:file.path) else{return};try unlink(file)
    }
    private func pagesURL(for record:AttachmentRecord)->URL{url(for:record).appendingPathExtension("pages")}
    func image(for record: AttachmentRecord) -> NSImage? { record.kind == .image ? NSImage(contentsOf:url(for:record)) : nil }
    func context(for records: [AttachmentRecord], leadingImages: Int = 0) throws -> FileContext {
        var result=FileContext()
        var textBudget=100_000
        var pageSources:[AttachmentRecord]=[]
        for record in records {
            let file=url(for:record)
            guard FileManager.default.fileExists(atPath:file.path) else { result.text += AttachmentRead.omission(record.name);continue }
            switch record.kind {
            case .image:
                do{
                    let data=try Data(contentsOf:file)
                    guard let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetCount(source)>0 else{result.text += AttachmentRead.omission(record.name);continue}
                    result.images.append(data)
                    result.text += ImageOrder.line(name:record.name,placedBefore:leadingImages,fileImagesSoFar:result.images.count)
                    pageSources.append(record)
                }catch{result.text += AttachmentRead.omission(record.name)}
            case .text:
                do{
                    let full=try String(contentsOf:file,encoding:.utf8)
                    guard !full.contains("\0") else{result.text += AttachmentRead.omission(record.name);continue}
                    let take=min(60_000,max(0,textBudget));let excerpt=String(full.prefix(take));textBudget-=excerpt.count
                    result.text += "\n--- File: \(record.name) ---\n\(excerpt)\n" + (full.count>take ? "[File text truncated; not all content is included.]\n" : "")
                }catch{result.text += AttachmentRead.omission(record.name)}
            case .pdf:
                do{
                    let piece=try onMain{try pdfPiece(file:file,name:record.name,textBudget:textBudget)}
                    result.text += piece.text;result.images += piece.images;textBudget-=piece.budgetUsed
                }catch{result.text += AttachmentRead.omission(record.name)}
            }
        }
        // Reserve primary images/PDF pages first; later pages cannot crowd out another file
        // or exceed the combined shared-window plus attachment image budget.
        for record in pageSources{appendLaterPages(of:record,into:&result,leadingImages:leadingImages)}
        guard result.images.count + max(0,leadingImages) <= 12 else { throw AppError("This chat includes too many visual pages. Remove a file or start a new chat; up to 12 images/pages fit in one request.") }
        return result
    }
    private func appendLaterPages(of record:AttachmentRecord,into result:inout FileContext,leadingImages:Int){
        guard let data=try? Data(contentsOf:pagesURL(for:record)),
              let source=CGImageSourceCreateWithData(data as CFData,nil) else{return}
        let count=CGImageSourceGetCount(source)
        let room=max(0,12-max(0,leadingImages)-result.images.count)
        let extra=ImagePages.extraPages(pageCount:count,extraRoom:room)
        var rendered=0
        if extra>0{
            for index in 1...extra{
                guard let png=imagePNG(source,index:index) else{continue}
                result.images.append(png);rendered+=1
                result.text += ImageOrder.line(name:record.name,placedBefore:leadingImages,fileImagesSoFar:result.images.count)
            }
        }
        if count>1{
            result.text += "\nImage pages for \(record.name): the first page and \(rendered) additional page(s) of \(count) were included. Do not imply access to any other pages.\n"
        }
    }
    private func onMain<T>(_ body:()throws->T)rethrows->T{
        if MainThread.mustHop(isMainThread:Thread.isMainThread){return try DispatchQueue.main.sync(execute:body)}
        return try body()
    }
    private struct PDFPiece{var text:String;var images:[Data];var budgetUsed:Int}
    private func pdfPiece(file:URL,name:String,textBudget:Int)throws->PDFPiece{
        guard let opened=PDFDocument(url:file),let pdf=Self.readablePDF(opened) else{throw AppError("Couldn’t open \(name).")}
        let maximum=min(60_000,max(0,textBudget))
        guard maximum>0 else{return PDFPiece(text:"\n[PDF \(name) is not included because the text context limit was reached.]\n",images:[],budgetUsed:0)}
        var text="";var bodies:[String]=[];var pagesRead=0
        for index in 0..<min(pdf.pageCount,300){
            let label="\n[Page \(index+1)]\n"
            guard text.count+label.count<maximum else{break}
            if let page=pdf.page(at:index){
                let body=String((page.string ?? "").prefix(maximum-text.count-label.count))
                text += label+body;bodies.append(body);pagesRead=index+1
            }
        }
        if PdfText.hasReadableText(pageBodies:bodies){
            var note="\n--- PDF: \(name) (\(pdf.pageCount) pages) ---\n\(text)\n"
            if pagesRead<pdf.pageCount || text.count>=maximum{note += "[PDF text truncated; only the preceding excerpt is available.]\n"}
            return PDFPiece(text:note,images:[],budgetUsed:text.count)
        }
        var images:[Data]=[]
        for index in 0..<min(4,pdf.pageCount){
            guard let page=pdf.page(at:index) else{continue}
            let image=page.thumbnail(of:NSSize(width:1200,height:1600),for:.mediaBox)
            if let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]){images.append(png)}
        }
        return PDFPiece(text:ScanPages.note(name:name,pageCount:pdf.pageCount,rendered:images.count),images:images,budgetUsed:0)
    }
}
