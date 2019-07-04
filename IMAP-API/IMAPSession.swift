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

public enum IMAPSessionError: Error {
    case unknownError
}

public typealias IMAPSessionParameters = (host: String, port: UInt32, username: String, password: String)

public class IMAPSession {
    private var session: MCOIMAPSession
    private let sessionParameters: IMAPSessionParameters

    private static func appendToLog(_ string: String) {
        print("[LOG] \(string)")
        appendToLog(string.data(using: .utf8))
    }

    private static func appendToLog(_ data: Data?) {
        do {
            let dir: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).last! as URL
            let url = dir.appendingPathComponent("mailSpamBotLog.txt")
            try data?.append(fileURL: url)
        } catch {
            print("Could not write to file")
        }
    }

    private static func createSession(sessionParameters p: IMAPSessionParameters) -> MCOIMAPSession {
        let session = MCOIMAPSession()
        session.hostname = p.host
        session.port = p.port
        session.username = p.username
        session.password = p.password
        session.connectionType = .TLS
        session.dispatchQueue = DispatchQueue.global()
        session.connectionLogger = { IMAPSession.appendToLog($2) }

        return session
    }

    public init(sessionParameters: IMAPSessionParameters) {
        self.sessionParameters = sessionParameters
        self.session = IMAPSession.createSession(sessionParameters: sessionParameters)
    }

    public func listFolders() -> SignalProducer<[MCOIMAPFolder], IMAPSessionError> {
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

    public func add(flags: MCOMessageFlag, toMessage withID: MailID, in folder: String) -> SignalProducer<(), IMAPSessionError> {
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

    public func move(message withID: MailID, from folder: String, to destinationFolder: String) -> SignalProducer<(), IMAPSessionError> {
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

    public func idle(on folder: String) -> SignalProducer<[MCOIMAPMessage], IMAPSessionError> {
        let semaphore = DispatchSemaphore(value: 0)
        var latestKnownUID: MailID = 0
        var idling = true

        var timer: Timer?
        var idleOperation: MCOIMAPIdleOperation?

        var startNextIDLEOperation: (() -> ())! = nil

        let timerClosure: (Timer) -> Void = { _ in
            IMAPSession.appendToLog("[IDLE] Session expired")
            idleOperation?.interruptIdle()
            idleOperation?.cancel()
//            self.session.disconnectOperation()!.start { _ in
//                self.session = IMAPSession.createSession(sessionParameters: self.sessionParameters)
//                startNextIDLEOperation()
//            }
            startNextIDLEOperation?()
        }

        startNextIDLEOperation = {
            timer?.invalidate()
            semaphore.signal()
            timer = Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: false, block: timerClosure)
        }

        self.fetchHeadersForContents(ofFolder: folder).startWithResult { result in
            if let messages = result.value {
                // latestKnownUID = messages.max(by: { $0.uid < $1.uid })?.uid ?? latestKnownUID
            }

            startNextIDLEOperation!()
        }

        return SignalProducer { observer, _ in
            DispatchQueue.global().async {
                while idling {
                    semaphore.wait()

                    IMAPSession.appendToLog("[IDLE] Session started")

                    // TODO Remove force unwrap
                    idleOperation = self.session.idleOperation(withFolder: folder, lastKnownUID: latestKnownUID)!
                    idleOperation?.start { error in
                        if error != nil {
                            idling = false
                            semaphore.signal()
                            return
                        }

                        let newMailRange = MCORangeMake(UInt64(latestKnownUID + 1), UINT64_MAX)
                        let newMailIndexSet = MCOIndexSet(range: newMailRange)

                        self.fetchHeadersForContents(ofFolder: folder, uids: newMailIndexSet!).startWithResult { result in
                            if let messages = result.value {
                                IMAPSession.appendToLog("[IDLE] Received \(messages.count) messages")
                                observer.send(value: messages)
                                // TODO This apparently causes trouble. Find a fix.
                                // latestKnownUID = messages.max(by: { $0.uid < $1.uid })?.uid ?? latestKnownUID
                            } else {
                                IMAPSession.appendToLog("[IDLE] Received notify but no new messages")
                            }

                            startNextIDLEOperation!()
//                            semaphore.signal()
                        }
                    }
                }
            }
        }
    }

    public func fetchHeadersForContents(ofFolder folder: String, uids: MCOIndexSet = MCOIndexSet(range: MCORangeMake(1, UINT64_MAX))) -> SignalProducer<[MCOIMAPMessage], IMAPSessionError> {
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

    public func fetchContentOfMail(withID uid: MailID, inFolder folder: String) -> SignalProducer<MailContent, IMAPSessionError> {
        guard let dataOperation = session.fetchMessageOperation(withFolder: folder, uid: uid) else {
            return SignalProducer(error: .unknownError)
        }

        return SignalProducer { observer, lifetime in
            dataOperation.start { (err, data) -> Void in
                autoreleasepool {
                    guard let parser = MCOMessageParser(data: data) else {
                        observer.send(error: .unknownError)
                        return
                    }

                    let mail = MailContent(fromParser: parser)

                    observer.send(value: mail)
                    observer.sendCompleted()
                }
            }
        }
    }
}

extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        }
        else {
            try write(to: fileURL, options: .atomic)
        }
    }
}
