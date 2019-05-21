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

public enum MailClassification: String, Codable, CustomDebugStringConvertible {
    public var debugDescription: String { return rawValue }

    case Spam
    //    case Newsletter
    //    case Acknowledged
    //    case Important
    case Ham

    public static let variants: [MailClassification] = [.Spam, .Ham] // [.Spam, .Newsletter, .Acknowledged, .Important]
}

public typealias MailID = UInt32
public typealias MailLocation = (folder: String, uid: MailID)

public struct MailSender: Codable {
    public let displayName: String?
    public let address: String?
}

public class MailContent: Codable {
    public let subject: String?
    public let body: String?
    public let htmlBody: String?
    public let sender: MailSender

    public var attachmentPaths: [URL]

    public init(subject: String?, body: String?, htmlBody: String?, sender: MailSender, attachmentPaths: [URL] = []) {
        self.subject = subject
        self.body = body
        self.htmlBody = htmlBody
        self.sender = sender
        self.attachmentPaths = attachmentPaths
    }

    public func imagesLinkedInHTML() -> [URL] {
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

    public func classifyableImages() -> SignalProducer<[Data], NoError> {
        // In order to prevent downloading of images which most likely contain tracking links this function will return
        // nothing for now until needed (e.g. for evaluation whether or not this actually takes place on a non-private inbox)
        return SignalProducer(value: [])

//        let minimumImageDimensions = CGFloat(500.0)
//
//        let linkedImages = Set(imagesLinkedInHTML())
//
//        return SignalProducer(linkedImages)
//            .filter { (imageURL: URL) -> Bool in
//                return imageURL.scheme.flatMap { $0 == "https" || $0 == "http" } ?? false
//            }
//            .flatMap(.concurrent(limit: 15)) { (imageURL: URL) -> SignalProducer<Data, NoError> in
//
//                let sessionConfiguration = URLSessionConfiguration.ephemeral
//                sessionConfiguration.waitsForConnectivity = true
//                sessionConfiguration.timeoutIntervalForRequest = 15
//                sessionConfiguration.timeoutIntervalForResource = 30
//                let session = URLSession(configuration: sessionConfiguration)
//                let request = URLRequest(url: imageURL)
//
//                return SignalProducer { observer, _ in
//                    print("\tFetching image", imageURL)
//                    session.dataTask(with: request) { data, response, error in
//                        if let data = data {
//                            if let image = NSImage(data: data), image.size.width > minimumImageDimensions, image.size.height > minimumImageDimensions {
//                                observer.send(value: data)
//                                print("\tFetched image", imageURL)
//                            }
//                        } else {
//                            print("\tImage download failure", imageURL, error?.localizedDescription ?? "no error")
//                        }
//                        observer.sendCompleted()
//                    }.resume()
//                }
//            }
//            .collect()
    }
}

extension DataRequest {
    private func responseSignalProducerIgnoringError() -> SignalProducer<Data, NoError> {
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
