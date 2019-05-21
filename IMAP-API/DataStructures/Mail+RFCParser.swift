//
//  Mail+RFCParser.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 17.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import MailCore

extension MailContent {
    public convenience init(fromParser parser: MCOMessageParser) {
        let sender = MailSender(displayName: parser.header.from?.displayName, address: parser.header.from?.mailbox)
        self.init(
            subject: parser.header.subject,
            body: parser.plainTextBodyRendering(),
            htmlBody: parser.htmlBodyRendering(),
            sender: sender
        )
    }

    public convenience init(fromData data: Data) throws {
        let parser = MCOMessageParser(data: data)!
        self.init(fromParser: parser)
    }
}
