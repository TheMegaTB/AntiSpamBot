//
//  MailWriter.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 17.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import IMAP_API
import ReactiveSwift
import Result

enum MailWriterContentType: String, CustomDebugStringConvertible {
    var debugDescription: String { return rawValue }

    case Subject
    case Body
    case HTMLBody
}

class MailWriter {
    let basePath: URL

    init(basePath: URL) {
        self.basePath = basePath
    }

    private func path(for classification: MailClassification, contentType: MailWriterContentType) throws -> URL {
        let path = basePath
            .appendingPathComponent(contentType.debugDescription)
            .appendingPathComponent(classification.debugDescription)
            .appendingPathComponent("\(UUID()).txt")

        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        return path
    }

    func write(mail: MailContent, to classification: MailClassification) throws {
        try autoreleasepool {
            let subjectPath = try path(for: classification, contentType: .Subject)
            let bodyPath = try path(for: classification, contentType: .Body)
            let htmlBodyPath = try path(for: classification, contentType: .HTMLBody)

            try mail.subject?.data(using: .utf8)?.write(to: subjectPath)
            try mail.body?.data(using: .utf8)?.write(to: bodyPath)
            try mail.htmlBody?.data(using: .utf8)?.write(to: htmlBodyPath)
        }
    }

    func write<T>(mails: MailSequence<T>, to classification: MailClassification, concurrencyCap: UInt = 500) -> SignalProducer<MailContent, AnyError> where T.Element == SignalProducer<MailContent, AnyError> {
        return SignalProducer(mails)
            .flatMap(.concurrent(limit: concurrencyCap)) { $0 }
            .on(value: { try! writer.write(mail: $0, to: classification) })
    }
}
