//
//  IMAPSession.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import MailCore
import ReactiveSwift

enum IMAPSessionError: Error {
    case unknownError
}

class IMAPSession {
    let session: MCOIMAPSession

    init(host: String, port: UInt32, username: String, password: String) {
        session = MCOIMAPSession()
        session.hostname = host
        session.port = port
        session.username = username
        session.password = password
        session.connectionType = .TLS
    }

    func fetchHeadersForContents(ofFolder folder: String) -> SignalProducer<[MCOIMAPMessage], IMAPSessionError> {
        let requestKind = MCOIMAPMessagesRequestKind.headers
        let uids = MCOIndexSet(range: MCORangeMake(1, UINT64_MAX))

        guard let fetchOperation = session.fetchMessagesOperation(withFolder: folder, requestKind: requestKind, uids: uids) else {
            return SignalProducer(error: .unknownError)
        }

        return SignalProducer { observer, lifetime in
            fetchOperation.start { (err, msg, vanished) -> Void in
                guard let messages = msg as? [MCOIMAPMessage] else {
                    observer.send(error: .unknownError)
                    return
                }

                observer.send(value: messages)
                observer.sendCompleted()
            }
        }
    }

    func fetchContentOfMail(withID uid: MailID, inFolder folder: String) -> SignalProducer<MailContent, IMAPSessionError> {
        guard let dataOperation = session.fetchMessageOperation(withFolder: folder, uid: uid) else {
            return SignalProducer(error: .unknownError)
        }

        return SignalProducer { observer, lifetime in
            dataOperation.start { (err, data) -> Void in
                guard let parser = MCOMessageParser(data: data) else {
                    observer.send(error: .unknownError)
                    return
                }

                let sender = MailSender(displayName: parser.header.from?.displayName, address: parser.header.from?.mailbox)
                let mail = MailContent(
                    subject: parser.header.subject,
                    body: parser.plainTextBodyRendering(),
                    htmlBody: parser.htmlBodyRendering(),
                    sender: sender
                )
                observer.send(value: mail)
                observer.sendCompleted()
            }
        }
    }
}
