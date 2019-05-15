//
//  main.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 10.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift

let serializationPath = "/Users/themegatb/Downloads/mails.json"

let args = CommandLine.arguments
let session = IMAPSession(host: args[1], port: UInt32(args[2])!, username: args[3], password: args[4])
let idleSession = IMAPSession(host: args[1], port: UInt32(args[2])!, username: args[3], password: args[4])

let engine = RuleEngine(session: session)
engine.rules = [
    ExecutableBoolRule(
        rule: KeywordRule("service@paypal.de", in: .senderAddress) && KeywordRule("mobilcom-debitel GmbH", in: .subject),
        action: RuleAction(action: .move(to: "Rechnungen/FUNK"), flag: .read)
    ),
    ExecutableBoolRule(
        rule: SpamClassificationRule(),
        action: .moveToJunk
    )
]

func downloadMails() {
    let academy = AntiSpamBotTrainingAcademy()

    academy.importMails(from: session, in: "AntiSpamBot/Training/Ham", as: .Ham)
        .then(academy.importMails(from: session, in: "AntiSpamBot/Training/Spam", as: .Spam))
        .startWithCompleted {
            try! academy.write(to: serializationPath)
            academy.mails.keys.forEach {
                print($0, academy.mails[$0]!.count)
            }
        }

    RunLoop.current.run()
}

func printWithInbox() {
    let antiSpamBot = AntiSpamBot()

    let folder = "Inbox"
    session.fetchHeadersForContents(ofFolder: folder)
        .flatten()
        .flatMap(.merge) { session.fetchContentOfMail(withID: $0.uid, inFolder: folder) }
        .on(value: { mailContent in
            antiSpamBot.predict(mail: mailContent).startWithResult {
                if let p = $0.value {
                    print("\nSubject: '\(mailContent.subject ?? "")'")
                    print("Sender: \(mailContent.sender.displayName ?? "") <\(mailContent.sender.address ?? "")>")
                    print("Classification: \(p.prediction?.debugDescription ?? "unknown")")
                    print("Confidence levels:")
                    p.printConfidenceLevels()
                }
            }
        })
        .startWithCompleted {
            print("Done")
        }

    RunLoop.current.run()
}

func train() {
    let academy = try! AntiSpamBotTrainingAcademy(path: serializationPath)
    try! academy.train()
}

func evaluate(contentsOf folder: String, as expectedClassification: MailClassification) -> SignalProducer<Double, AnyError> {
    let antiSpamBot = AntiSpamBot()

    return session.fetchHeadersForContents(ofFolder: folder)
        .flatten()
        .flatMap(.merge) { session.fetchContentOfMail(withID: $0.uid, inFolder: folder) }
        .mapError { AnyError($0) }
        .flatMap(.merge) { antiSpamBot.predict(mail: $0) }
        .filter { $0.prediction != nil }
        .map { $0.prediction! == expectedClassification }
        .collect()
        .map { (matchList: [Bool]) -> Double in
            print("Classified \(matchList.count) mails.")
            let matchCount: Int = matchList.reduce(0) { $1 ? $0 + 1 : $0 }
            return Double(matchCount) / Double(matchList.count)
        }
}

func evaluate() {
    evaluate(contentsOf: "AntiSpamBot/Evaluation/Spam", as: .Spam)
        .merge(with: evaluate(contentsOf: "AntiSpamBot/Evaluation/Ham", as: .Ham))
        .collect()
        .map { $0.reduce(0.0) { $0 + $1 } / Double($0.count) }
        .startWithResult { result in
            print("Accuracy on evaluation dataset:", result.value ?? 0)
            print("Evaluation error:", result.error)
            exit(0)
        }

    RunLoop.current.run()
}

func ruleInbox() {
    let folder = "Inbox"
    session.fetchHeadersForContents(ofFolder: folder)
        .flatten()
        .startWithResult { result in
            if let mail = result.value {
                engine.apply(toMailAt: (folder: folder, uid: mail.uid)).start()
            }
        }

    RunLoop.current.run()
}

//downloadMails()
//train()
//printWithInbox()
//evaluate()
//ruleInbox()

let folder = "INBOX"
idleSession.idle(on: folder).startWithResult { result in
    if let messages = result.value {
        messages.forEach { message in
            print("[\(message.uid)] \(message.header.from.rfc822String() ?? "") => \(message.header.subject ?? "")")

            engine.apply(toMailAt: (folder: folder, uid: message.uid)).start()
        }
    } else if let error = result.error {
        print("IDLE failed.", error.localizedDescription)
    }
}

print("IDLE listening ...")
RunLoop.current.run()
