//
//  main.swift
//  DataPreparationTool
//
//  Created by Til Blechschmidt on 17.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import IMAP_API
import ReactiveSwift
import Result

let args = CommandLine.arguments
let parameters = (host: args[1], port: UInt32(args[2])!, username: args[3], password: args[4])
let session = IMAPSession(sessionParameters: parameters)


let folder = URL(fileURLWithPath: "/Users/themegatb/Downloads/spamDL/2018/")
var fsSource = FilesystemMailContentSource(folder: folder, fileExtension: "txt")


let remoteSpamSource = IMAPMailContentSource.create(withContentsOf: "AntiSpamBot/Training/Spam", in: session)
let remoteHamSource = IMAPMailContentSource.create(withContentsOf: "AntiSpamBot/Training/Ham", in: session)

let writer = MailWriter(basePath: URL(fileURLWithPath: "/Users/themegatb/Downloads/spamDL/labelled"))

//let filesystemSequence = MailSequence(of: fsSource!)
//var x = 0
//var total = 0
//writer.write(mails: filesystemSequence, to: .Spam)
//    .on(value: { _ in
//        print("\(x) / \(total)")
//        x += 1
//    })
//    .startWithCompleted {
//        print("done")
//    }

remoteHamSource.pipe(into: writer, classification: .Ham)
    .then(remoteSpamSource.pipe(into: writer, classification: .Spam))
    .startWithCompleted {
        print("done")
    }

RunLoop.current.run()
