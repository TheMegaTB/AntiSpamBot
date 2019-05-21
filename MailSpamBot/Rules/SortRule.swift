//
//  SortRule.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 16.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result
import IMAP_API

class SortRule: BoolRule {
    let boolRule: BoolRule

    init(from: String, subjectContains: String) {
        boolRule = KeywordRule(from, in: .senderAddress) && KeywordRule(subjectContains, in: .subject)
    }

    func triggers(on mail: MailContent) -> SignalProducer<Bool, NoError> {
        return boolRule.triggers(on: mail)
    }
}

class ExecutableSortRule: ExecutableBoolRule {
    init(from: String, subjectContains: String, moveTo: String) {
        super.init(
            rule: SortRule(from: from, subjectContains: subjectContains),
            action: RuleAction(.move(to: moveTo))
        )
    }
}
