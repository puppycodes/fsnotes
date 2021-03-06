//
//  ImagesProcessor.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 1/12/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

public class ImagesProcessor {
    var textStorageNSString: NSString
    var styleApplier: NSMutableAttributedString
    var range: NSRange?
    var maxWidth: CGFloat
    var note: Note
    var paragraphRange: NSRange
    
    var offset = 0
    var newLineOffset = 0
    
    init(styleApplier: NSMutableAttributedString, range: NSRange? = nil, maxWidth: CGFloat, note: Note) {
        self.styleApplier = styleApplier
        self.range = range
        self.maxWidth = maxWidth
        self.note = note
        self.textStorageNSString = styleApplier.string as NSString
        
        if let unwrappedRange = range {
            paragraphRange = unwrappedRange
        } else {
            paragraphRange = NSRange(0..<styleApplier.length)
        }
    }
    
    public func load() {
        let string = styleApplier.string
        
        NotesTextProcessor.imageInlineRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            
            let mdLink = self.textStorageNSString.substring(with: range)
            let mdTitleLength = self.computeMarkdownTitleLength(mdLink: mdLink)
            
            self.styleApplier.addAttribute(.font, value: UserDefaultsManagement.noteFont, range: range)
            
            NotesTextProcessor.imageOpeningSquareRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                self.styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            
            NotesTextProcessor.imageClosingSquareRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                self.styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            
            NotesTextProcessor.parenRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                
                self.styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                
                var url: URL?
                var isCached = false
                
                let filePath = self.getFilePath(innerRange: innerRange)
                if let localNotePath = self.getLocalNotePath(path: filePath, innerRange: innerRange), FileManager.default.fileExists(atPath: localNotePath) {
                    url = URL(fileURLWithPath: localNotePath)
                    isCached = true
                } else if let fs = URL(string: filePath) {
                    url = fs
                }
                
                guard let imageURL = url, let imageData = try? Data(contentsOf: imageURL), let image = NSImage(data: imageData) else {
                    return
                }
                
                if !isCached {
                    _ = self.writeImage(data: imageData, url: imageURL)
                }
                
                self.replaceAttributedString(innerRange: innerRange, mdTitleLength: mdTitleLength, image: image)
            }
        }
    }
    
    func computeMarkdownTitleLength(mdLink: String) -> Int {
        var mdTitleLength = 0
        if let match = mdLink.range(of: "\\[(.+)\\]", options: .regularExpression) {
            mdTitleLength = mdLink[match].count - 2
        }
        
        return mdTitleLength
    }
    
    func getLocalNotePath(path: String, innerRange: NSRange) -> String? {
        var notePath: String
        
        guard let noteStorage = self.note.storage, let storagePath = noteStorage.getPath() else {
            return nil
        }
        
        if path.starts(with: "http://") || path.starts(with: "https://"), let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            notePath = storagePath + "/i/" + encodedPath
            return notePath
        } else if let path = getFilePath(innerRange: innerRange).removingPercentEncoding {
            notePath = storagePath + "/" + path
            return notePath
        }
        
        return nil
    }
    
    func getFilePath(innerRange: NSRange) -> String {
        let link = NSRange(location: innerRange.location + 1, length: innerRange.length - 2)
        let path = textStorageNSString.substring(with: link)
        return path
    }
    
    func getFileName(from: URL, to: URL) -> String? {
        var name: String?
        let path = from.absoluteString
        
        if path.starts(with: "http://") || path.starts(with: "https://"), let webName = path.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            name = webName
        }
        
        if path.starts(with: "file://") {
            var i = 0
            var pathComponent = from.lastPathComponent
            let ext = from.pathExtension
            
            while name == nil {
                let destination = to.appendingPathComponent(pathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    i = i + 1
                    pathComponent = "\(i).\(ext)"
                    continue
                }
                
                name = pathComponent
            }
        }

        return name
    }
    
    func writeImage(data: Data, url: URL) -> String? {
        if let noteStorage = self.note.storage, let storagePath = noteStorage.getPath() {
            
            let destination = URL(fileURLWithPath: storagePath + "/i/")
            _ = makeInitialDirectory(cacheURL: destination)
            
            guard let fileName = getFileName(from: url, to: destination) else {
                return nil
            }
            
            let to = destination.appendingPathComponent(fileName)
            try? data.write(to: to, options: .atomic)
            
            return fileName
        }
        
        return nil
    }
    
    func makeInitialDirectory(cacheURL: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: false, attributes: nil)
            return true
        } catch {
            return false
        }
    }
    
    func computeInEditorSize(image: NSImage) -> NSSize {
        let realSize = image.representations[0]
        var scale: CGFloat = 1
        
        if CGFloat(realSize.pixelsWide) > self.maxWidth {
            scale = (self.maxWidth - 20) / CGFloat(realSize.pixelsWide)
        }
        
        let width = CGFloat(realSize.pixelsWide) * scale
        let height = CGFloat(realSize.pixelsHigh) * scale
        
        return NSSize(width: width, height: height)
    }
    
    func getImageAttributedString(image: NSImage) -> NSAttributedString {
        image.size = self.computeInEditorSize(image: image)
                
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 15
        
        let fileWrapper = FileWrapper.init()
        fileWrapper.icon = image
                
        let attachment = NSTextAttachment()
        attachment.fileWrapper = fileWrapper
        
        let attributedString = NSAttributedString(attachment: attachment)
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        mutableString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(0..<1))
        mutableString.addAttribute(.baselineOffset, value: -15, range: NSRange(0..<1))
        
        return mutableString
    }
    
    func isContainAttachment(innerRange: NSRange, mdTitleLength: Int) -> Bool {
        let j = offset + newLineOffset - mdTitleLength
        
        if innerRange.lowerBound >= 5 + mdTitleLength {
            return self.styleApplier.containsAttachments(in: NSMakeRange(innerRange.lowerBound - 5 + j, 1))
        }
        
        return false
    }
    
    func isContainNewLine(innerRange: NSRange, mdTitleLength: Int) -> Bool {
        let j = offset + newLineOffset - mdTitleLength
        
        if innerRange.lowerBound >= 4 + mdTitleLength {
            return (self.styleApplier.attributedSubstring(from: NSMakeRange(innerRange.lowerBound - 4 + j, 1)).string == "\n")
        }
        
        return false
    }
    
    func replaceAttributedString(innerRange: NSRange, mdTitleLength: Int, image: NSImage) {
        let attrStringWithImage = self.getImageAttributedString(image: image)
        
        guard self.styleApplier.length >= innerRange.location + innerRange.length else {
            return
        }
        
        let attachmentExist = self.isContainAttachment(innerRange: innerRange, mdTitleLength: mdTitleLength)
        
        let newLine = self.isContainNewLine(innerRange: innerRange, mdTitleLength: mdTitleLength)
        
        let j = offset + newLineOffset - mdTitleLength
        
        guard !attachmentExist else {
            self.styleApplier.replaceCharacters(in: NSMakeRange(innerRange.lowerBound - 5 + j, 1), with: attrStringWithImage)
            return
        }
        
        if !newLine {
            self.styleApplier.replaceCharacters(in: NSMakeRange(innerRange.lowerBound - 3 + j, 0), with: NSAttributedString(string: "\n"))
            self.styleApplier.replaceCharacters(in: NSMakeRange(innerRange.lowerBound - 3 + j, 0), with: attrStringWithImage)
            
            offset = offset + 2
        } else {
            self.styleApplier.replaceCharacters(in: NSMakeRange(innerRange.lowerBound - 4 + j, 0), with: attrStringWithImage)
            
            offset = offset + 1
        }
    }
}
