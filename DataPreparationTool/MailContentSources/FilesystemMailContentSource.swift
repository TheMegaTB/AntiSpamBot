//
//  FilesystemMailContentSource.swift
//  DataPreparationTool
//
//  Created by Til Blechschmidt on 18.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import MailCore
import IMAP_API
import ReactiveSwift
import Result

struct FilesystemMailContentSource: MailContentSource {
    let enumerator: FileManager.DirectoryEnumerator
    let fileExtension: String

    init?(folder: URL, fileExtension: String) {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }

        self.enumerator = enumerator
        self.fileExtension = fileExtension
    }

    var totalCount: Int? {
        return nil
    }

    private func nextURL() -> URL? {
        guard let nextObjectURL = enumerator.nextObject() as? URL else {
            return nil
        }

        if nextObjectURL.pathExtension == fileExtension {
            return nextObjectURL
        } else {
            // TODO Do this non-recursively
            return nextURL()
        }
    }

    mutating func next() -> SignalProducer<MailContent, AnyError>? {
        guard let nextURL = nextURL() else {
            return nil
        }

        guard let data = try? Data(contentsOf: nextURL) else {
            return nil
        }

        let mailContent = autoreleasepool { try? MailContent(fromData: data) }
        guard let unwrappedMailContent = mailContent else {
            return nil
        }

        return SignalProducer(value: unwrappedMailContent)
    }
}
