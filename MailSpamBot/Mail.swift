//
//  Mail.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import SwiftSoup
import Alamofire
import ReactiveSwift
import Result
import Cocoa

struct Constants {
    static var session: Session = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10

        return Session(configuration: configuration)
    }()
}

typealias MailID = UInt32

struct MailSender: Codable {
    let displayName: String?
    let address: String?
}

class MailContent: Codable {
    let subject: String?
    let body: String?
    let htmlBody: String?
    let sender: MailSender

    var attachmentPaths: [URL]

    init(subject: String?, body: String?, htmlBody: String?, sender: MailSender, attachmentPaths: [URL] = []) {
        self.subject = subject
        self.body = body
        self.htmlBody = htmlBody
        self.sender = sender
        self.attachmentPaths = attachmentPaths
    }

    func imagesLinkedInHTML() -> [URL] {
        guard let htmlBody = self.htmlBody else {
            return []
        }

        do {
            let doc = try SwiftSoup.parse(htmlBody)
            let images = try doc.select("img")
            let imageSources = try images.map { image in
                return try image.attr("src")
            }

            return imageSources.compactMap { URL(string: $0) }
        } catch {
            print(error)
            return []
        }
    }

    func classifyableImages() -> SignalProducer<[Data], NoError> {
        let minimumImageDimensions = CGFloat(500.0)

        return SignalProducer(imagesLinkedInHTML())
            .flatMap(.merge) { imageURL in
                let request = Constants.session.request(imageURL)

                return request.responseSignalProducerIgnoringError()
                    .filter { data in
                        // TODO Migrate this to CoreGraphics
                        return NSImage(data: data).flatMap {
                            $0.size.width > minimumImageDimensions && $0.size.height > minimumImageDimensions
                        } ?? false
                    }
            }
            .collect()
    }
}

extension DataRequest {
    func responseSignalProducerIgnoringError() -> SignalProducer<Data, NoError> {
        return SignalProducer { observer, lifetime in
            self.response { response in
                if let data = response.value ?? nil {
                    observer.send(value: data)
                    observer.sendCompleted()
                } else {
                    observer.sendCompleted()
                }
            }
        }
    }
}
