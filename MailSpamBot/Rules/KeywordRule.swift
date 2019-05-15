//
//  KeywordRule.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result

struct KeywordLocation: OptionSet {
    let rawValue: UInt8

    static let senderAddress = KeywordLocation(rawValue: 1 << 0)
    static let senderName = KeywordLocation(rawValue: 1 << 1)
    static let subject = KeywordLocation(rawValue: 1 << 2)
    static let body = KeywordLocation(rawValue: 1 << 3)
}

class KeywordRule: BoolRule {
    let locations: KeywordLocation
    let keyword: String

    init(_ keyword: String, in locations: KeywordLocation) {
        self.keyword = keyword
        self.locations = locations
    }

    func triggers(on mail: MailContent) -> SignalProducer<Bool, NoError> {
        let keywordFound = locations.contains(.senderAddress) && mail.sender.address.flatMap { $0.contains(keyword) } ?? false
            || locations.contains(.senderName) && mail.sender.displayName.flatMap { $0.contains(keyword) } ?? false
            || locations.contains(.subject) && mail.subject.flatMap { $0.contains(keyword) } ?? false
            || locations.contains(.body) && mail.body.flatMap { $0.contains(keyword) } ?? false

        return SignalProducer(value: keywordFound)
    }
}
