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
        session.dispatchQueue = DispatchQueue.global()

//        session.connectionLogger = { _, _, data in
//            print(String(data: data!, encoding: .utf8)!)
//        }
    }

    func listFolders() -> SignalProducer<[MCOIMAPFolder], IMAPSessionError> {
        guard let listFoldersOperation = session.fetchAllFoldersOperation() else {
            return SignalProducer(error: IMAPSessionError.unknownError)
        }

        return SignalProducer { observer, _ in
            listFoldersOperation.start { error, folders in
                if let folders = folders as? [MCOIMAPFolder] {
                    print(folders.map { $0.path })
                    observer.send(value: folders)
                }

                // TODO Process error

                observer.sendCompleted()
            }
        }
    }

    func add(flags: MCOMessageFlag, toMessage withID: MailID, in folder: String) -> SignalProducer<(), IMAPSessionError> {
        let uidSet = MCOIndexSet(index: UInt64(withID))
        guard let flagOperation = session.storeFlagsOperation(withFolder: folder, uids: uidSet, kind: .add, flags: flags) else {
            return SignalProducer(error: IMAPSessionError.unknownError)
        }

        return SignalProducer { observer, lifetime in
            flagOperation.start { error in
                guard error == nil else {
                    observer.send(error: .unknownError)
                    return
                }

                observer.send(value: ())
                observer.sendCompleted()
            }
        }
    }

    func move(message withID: MailID, from folder: String, to destinationFolder: String) -> SignalProducer<(), IMAPSessionError> {
        let uidSet = MCOIndexSet(index: UInt64(withID))

        guard let moveOperation = session.moveMessagesOperation(withFolder: folder, uids: uidSet, destFolder: destinationFolder) else {
            return SignalProducer(error: IMAPSessionError.unknownError)
        }

        return SignalProducer { observer, lifetime in
            moveOperation.start { error, _ in
                guard error == nil else {
                    observer.send(error: .unknownError)
                    return
                }

                observer.send(value: ())
                observer.sendCompleted()
            }
        }
    }

    func idle(on folder: String) -> SignalProducer<[MCOIMAPMessage], IMAPSessionError> {
        let semaphore = DispatchSemaphore(value: 0)
        var latestKnownUID: MailID = 0
        var idling = true

        self.fetchHeadersForContents(ofFolder: folder).startWithResult { result in
            if let messages = result.value {
                latestKnownUID = messages.max(by: { $0.uid < $1.uid })?.uid ?? latestKnownUID
            }

            semaphore.signal()
        }

        return SignalProducer { observer, _ in
            DispatchQueue.global().async {
                while idling {
                    semaphore.wait()

                    // TODO Remove force unwrap
                    let op = self.session.idleOperation(withFolder: folder, lastKnownUID: latestKnownUID)!
                    op.start { error in
                        if error != nil {
                            idling = false
                            semaphore.signal()
                            return
                        }

                        let newMailRange = MCORangeMake(UInt64(latestKnownUID + 1), UINT64_MAX)
                        let newMailIndexSet = MCOIndexSet(range: newMailRange)

                        self.fetchHeadersForContents(ofFolder: folder, uids: newMailIndexSet!).startWithResult { result in
                            if let messages = result.value {
                                observer.send(value: messages)
                                latestKnownUID = messages.max(by: { $0.uid < $1.uid })?.uid ?? latestKnownUID
                            }

                            semaphore.signal()
                        }
                    }
                }
            }
        }
    }

    func fetchHeadersForContents(ofFolder folder: String, uids: MCOIndexSet = MCOIndexSet(range: MCORangeMake(1, UINT64_MAX))) -> SignalProducer<[MCOIMAPMessage], IMAPSessionError> {
        let requestKind = MCOIMAPMessagesRequestKind.headers

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
