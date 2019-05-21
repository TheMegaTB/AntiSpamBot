//
//  IMAPMailContentSource.swift
//  DataPreparationTool
//
//  Created by Til Blechschmidt on 18.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import MailCore
import IMAP_API
import ReactiveSwift
import Result

struct IMAPMailContentSource: MailContentSource {
    let session: IMAPSession
    let folder: String
    var headers: [MCOIMAPMessage]

    static func create(withContentsOf folder: String, in session: IMAPSession) -> SignalProducer<IMAPMailContentSource, IMAPSessionError> {
        return session.fetchHeadersForContents(ofFolder: folder)
            .map { IMAPMailContentSource(session: session, folder: folder, headers: $0) }
    }

    var totalCount: Int? {
        return headers.count
    }

    mutating func next() -> SignalProducer<MailContent, AnyError>? {
        guard let nextMail = headers.popLast() else {
            return nil
        }

        return session.fetchContentOfMail(withID: nextMail.uid, inFolder: folder)
            .mapError { AnyError($0) }
    }
}

extension SignalProducer where Value == IMAPMailContentSource {
    func pipe(into writer: MailWriter, classification: MailClassification) -> SignalProducer<MailContent, AnyError> {
        var x = 0
        var total = 0
        return self.mapError { AnyError($0) }
            .on(value: { source in total = source.totalCount ?? 0 })
            .flatMap(.merge) { writer.write(mails: MailSequence(of: $0), to: classification) }
            .on(value: { _ in
                print("\(x) / \(total)")
                x += 1
            })
    }
}
