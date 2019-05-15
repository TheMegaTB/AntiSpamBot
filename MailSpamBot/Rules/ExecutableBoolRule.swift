//
//  BoolRule.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result

protocol BoolRule {
    func triggers(on mail: MailContent) -> SignalProducer<Bool, NoError>
}

struct ExecutableBoolRule: ExecutableRule {
    let rule: BoolRule
    let action: RuleAction

    func determineAction(on mail: MailContent) -> SignalProducer<RuleAction, NoError> {
        return rule.triggers(on: mail).filterMap {
            if $0 {
                return self.action
            }

            return nil
        }
    }
}

struct AndRule: BoolRule {
    let lhs: BoolRule
    let rhs: BoolRule

    func triggers(on mail: MailContent) -> SignalProducer<Bool, NoError> {
        return lhs.triggers(on: mail).and(rhs.triggers(on: mail))
    }
}

struct OrRule: BoolRule {
    let lhs: BoolRule
    let rhs: BoolRule

    func triggers(on mail: MailContent) -> SignalProducer<Bool, NoError> {
        return lhs.triggers(on: mail).or(rhs.triggers(on: mail))
    }
}

func &&(left: BoolRule, right: BoolRule) -> BoolRule {
    return AndRule(lhs: left, rhs: right)
}

func ||(left: BoolRule, right: BoolRule) -> BoolRule {
    return OrRule(lhs: left, rhs: right)
}
