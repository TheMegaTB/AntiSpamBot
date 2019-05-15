//
//  RuleEngine.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result

enum RuleEngineError: Error {
    case unknownError
}

class RuleEngine {
    let session: IMAPSession
    var rules: [ExecutableRule] = []

    init(session: IMAPSession) {
        self.session = session
    }

    func apply(toMailAt location: MailLocation) -> SignalProducer<(), IMAPSessionError> {
        return session.fetchContentOfMail(withID: location.uid, inFolder: location.folder)
            .flatMap(.merge) { self.determineAction(on: $0) }
            .on(value: {
                print($0)
            })
            .flatMap(.merge) { self.applyAction($0, toMailAt: location) }
    }

    func applyAction(_ action: RuleAction, toMailAt location: MailLocation) -> SignalProducer<(), IMAPSessionError> {
        var producer = SignalProducer<(), IMAPSessionError> { observer, _ in observer.sendCompleted() }

        if action.flag.contains(.read) {
            producer = producer.then(session.add(flags: .seen, toMessage: location.uid, in: location.folder))
        }

        if action.flag.contains(.flagged) {
            producer = producer.then(session.add(flags: .flagged, toMessage: location.uid, in: location.folder))
        }

        switch action.action {
        case .junk:
            // TODO Flag mail as junk *somehow*
            producer = producer.then(session.move(message: location.uid, from: location.folder, to: "Junk"))
        case .trash:
            producer = producer.then(session.move(message: location.uid, from: location.folder, to: "Trash"))
        case .move(let to):
            producer = producer.then(session.move(message: location.uid, from: location.folder, to: to))
        case .keep:
            break
        }

        return producer
    }

    func determineAction(on mail: MailContent) -> SignalProducer<RuleAction, NoError> {
        let ruleProducers = rules.map { $0.determineAction(on: mail) }

        return SignalProducer.merge(ruleProducers).take(first: 1)
    }
}
