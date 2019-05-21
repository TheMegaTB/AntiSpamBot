//
//  MailContentSource.swift
//  DataPreparationTool
//
//  Created by Til Blechschmidt on 17.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import IMAP_API
import ReactiveSwift
import Result

protocol MailContentSource: IteratorProtocol {
    associatedtype Element = SignalProducer<MailContent, AnyError>

    var totalCount: Int? { get }
}

struct MailSequence<T: MailContentSource>: Sequence {
    typealias Iterator = T
    typealias Element = T.Element

    private let iterator: T

    init(of: T) {
        iterator = of
    }

    func makeIterator() -> T {
        return iterator
    }
}
