//
//  AntiSpamBotTrainingAcademy.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import ReactiveSwift
import CreateML
import Cocoa
import Result

class AntiSpamBotTrainingAcademy {
    var mails: [MailClassification: [MailContent]]

    let mlModelPath = URL(fileURLWithPath: "/Users/themegatb/Downloads/SpamModels/")
    let storagePath = URL(fileURLWithPath: "/Users/themegatb/Downloads/MailCache")

    init() {
        mails = MailClassification.variants.reduce(into: [:]) { $0[$1] = [] }
    }

    init(path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: fileURL)
        let decodedMails = try decoder.decode([MailClassification: [MailContent]].self, from: data)
        self.mails = decodedMails
    }

    func write(to path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let encoder = JSONEncoder()
        let encodedMails = try encoder.encode(mails)
        try encodedMails.write(to: fileURL)
    }

    func addMail(ofType type: MailClassification, withContent content: MailContent) -> SignalProducer<(), NoError> {
        // print("\tAdding mail:", content.subject, content.sender.address)
        let fileManager = FileManager.default

        let attachmentsStoragePath = storagePath.appendingPathComponent("Attachments", isDirectory: true)
        try! fileManager.createDirectory(at: attachmentsStoragePath, withIntermediateDirectories: true, attributes: nil)

        let images = content.classifyableImages()

        return images
            .flatten()
            .map { (image: Data) -> URL in
                let attachmentID = UUID()
                let attachmentPath = attachmentsStoragePath.appendingPathComponent(attachmentID.uuidString)

                try? image.write(to: attachmentPath)

                return attachmentPath
            }
            .collect()
            .map { urls in
                content.attachmentPaths = urls
                self.mails[type]?.append(content)
            }
    }

    func importMails(from session: IMAPSession, in folder: String, as type: MailClassification) -> SignalProducer<(), IMAPSessionError> {
        var totalAmount = 0
        var processedAmount = 0

        return session.fetchHeadersForContents(ofFolder: folder)
            .on(value: { totalAmount = $0.count })
            .flatten()
            .flatMap(.concurrent(limit: 15)) { session.fetchContentOfMail(withID: $0.uid, inFolder: folder) }
            .flatMap(.concurrent(limit: 1)) { self.addMail(ofType: type, withContent: $0) }
            .on(value: { _ in
                processedAmount += 1
                print("[C] \(type): \(processedAmount) / \(totalAmount)")
            })
            .on(completed: {
                print("Completed2!")
            })
    }

    private func prepareTextTrainingData() throws -> MLDataTable {
        var rawData: [String: MLDataValueConvertible] = [:]

        rawData["Type"] = mails.keys.flatMap { Array(repeating: $0.rawValue, count: mails[$0]!.count ) }

        let combinedMails = mails.flatMap { $0.value }

        // TODO We might have to filter out mails in general that don't have the necessary data
        rawData["Content"] = combinedMails.map { $0.body ?? "" }
        rawData["Subject"] = combinedMails.map { $0.subject ?? "" }
        rawData["SenderAdress"] = combinedMails.map { $0.sender.address ?? "" }

        return try MLDataTable(dictionary: rawData)
    }

    private func printAccuracy(of classifier: MLTextClassifier, with testingData: MLDataTable) {
        // Training accuracy as a percentage
        let trainingAccuracy = (1.0 - classifier.trainingMetrics.classificationError) * 100

        // Validation accuracy as a percentage
        let validationAccuracy = (1.0 - classifier.validationMetrics.classificationError) * 100

        // Evaluation accuracy as a percentage
        let evaluationMetrics = classifier.evaluation(on: testingData)
        let evaluationAccuracy = (1.0 - evaluationMetrics.classificationError) * 100

        print("Accuracy on training data:\t\t", trainingAccuracy)
        print("Accuracy on validation data:\t", validationAccuracy)
        print("Accuracy on evaluation data:\t", evaluationAccuracy)
    }

    private func trainImages() throws -> MLImageClassifier {
        let urlsByCategory: [String: [URL]] = mails.reduce(into: [:]) { (result, entry) in
            let (key, value) = entry

            if result[key.rawValue] == nil {
                result[key.rawValue] = []
            }

            let imageURLs = value.flatMap { $0.attachmentPaths }

            result[key.rawValue]?.append(contentsOf: imageURLs)
        }

        let shuffledURLs = urlsByCategory.mapValues { $0.shuffled() }
        let trainingDataSize = 0.8
        let trainingData = shuffledURLs.mapValues { Array($0[..<(Int(Double($0.count) * trainingDataSize))]) }
        let evaluationData = shuffledURLs.mapValues { Array($0[(Int(Double($0.count) * trainingDataSize))...]) }

        let classifier = try MLImageClassifier(trainingData: trainingData)
        let evaluation = classifier.evaluation(on: evaluationData)

        print("\n\n--- Image classifier:")
        print("Accuracy on training data:\t\t", (1.0 - classifier.trainingMetrics.classificationError) * 100)
        print("Accuracy on validation data:\t", (1.0 - classifier.validationMetrics.classificationError) * 100)
        print("Accuracy on evaluation data:\t", (1.0 - evaluation.classificationError) * 100)

        return classifier
    }

    func train() throws {
        let (textTrainingData, textTestingData) = try prepareTextTrainingData().randomSplit(by: 0.8, seed: 5)

        let bodyClassifier = try MLTextClassifier(trainingData: textTrainingData, textColumn: "Content", labelColumn: "Type")
        let subjectClassifier = try MLTextClassifier(trainingData: textTrainingData, textColumn: "Subject", labelColumn: "Type")

        let imageClassifier = try trainImages()

        print("\n\n--- Subject classifier:")
        printAccuracy(of: subjectClassifier, with: textTestingData)
        print("\n\n--- Body classifier:")
        printAccuracy(of: bodyClassifier, with: textTestingData)

        let classifierMetadata = MLModelMetadata(author: "Til Blechschmidt",
                                                 shortDescription: "A model trained to classify emails as spam/ham",
                                                 version: "1.0")

        try bodyClassifier.write(to: mlModelPath.appendingPathComponent("BodyModel.mlmodel"), metadata: classifierMetadata)
        try subjectClassifier.write(to: mlModelPath.appendingPathComponent("SubjectModel.mlmodel"), metadata: classifierMetadata)
        try imageClassifier.write(to: mlModelPath.appendingPathComponent("AttachmentModel.mlmodel"), metadata: classifierMetadata)
    }
}
