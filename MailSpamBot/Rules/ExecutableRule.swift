//
//  ExecutableRule.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result

enum MailAction {
    case keep
    case junk
    case trash
    case move(to: String)
}

struct MailFlags: OptionSet {
    let rawValue: UInt8

    static let read = MailFlags(rawValue: 1 << 0)
    static let flagged = MailFlags(rawValue: 1 << 1)
}

struct RuleAction {
    let action: MailAction
    let flag: MailFlags

    static let markAsRead = RuleAction(action: .keep, flag: .read)
    static let moveToJunk = RuleAction(action: .junk, flag: [])
    static let trash = RuleAction(action: .trash, flag: [])

    init(action: MailAction, flag: MailFlags) {
        self.action = action
        self.flag = flag
    }

    init(_ action: MailAction) {
        self.init(action: action, flag: [])
    }

    init(_ flag: MailFlags) {
        self.init(action: .keep, flag: flag)
    }
}

protocol ExecutableRule {
    func determineAction(on mail: MailContent) -> SignalProducer<RuleAction, NoError>
}
