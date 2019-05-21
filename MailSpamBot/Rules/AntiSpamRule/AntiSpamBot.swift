//
//  AntiSpamBot.swift
//  MailSpamBot
//
//  Created by Til Blechschmidt on 14.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import Vision
import ReactiveSwift
import Result
import IMAP_API

class MailClassificationPrediction {
    static let empty = MailClassificationPrediction(confidenceLevels: [:])

    let confidenceLevels: [MailClassification: Double]

    init(confidenceLevels: [MailClassification: Double]) {
        // TODO Check that all classifications are in there
        self.confidenceLevels = confidenceLevels
    }

    convenience init(byMerging sequence: [MailClassificationPrediction]) {
        let weights = Array(repeating: 1 / Double(sequence.count), count: sequence.count)
        try! self.init(byMerging: sequence, weightedBy: weights)
    }

    init(byMerging sequence: [MailClassificationPrediction], weightedBy weights: [Double]) throws {
        assert(sequence.count == weights.count, "Attempted to init MailClassificationPrediction with a mismatching number of weights")
        assert(sequence.count == 0 || weights.reduce(0.0) { $0 + $1 } == 1.0, "Attempted to init MailClassificationPrediction with a set of weights not summing up to 1.0")

        confidenceLevels = MailClassification.variants.reduce(into: [:]) { result, classification in
            let sumOfWeightedConfidences = zip(sequence, weights).reduce(0.0) { sum, sequences in
                let (prediction, weight) = sequences
                return sum + prediction[classification] * weight
            }

            result[classification] = sumOfWeightedConfidences
        }
    }

    func weighted(by weight: Double) -> MailClassificationPrediction {
        return MailClassificationPrediction(confidenceLevels: confidenceLevels.mapValues { $0 * weight })
    }

    var prediction: MailClassification? {
        // TODO If the confidence is below a certain value (e.g. 50%) return nil
        return confidenceLevels.max { $0.value < $1.value }.flatMap { $0.key }
    }

    func printConfidenceLevels() {
        confidenceLevels.sorted { $0.key.rawValue < $1.key.rawValue }.forEach {
            print("\t\($0.key): \(round($0.value * 10_000) / 100)%")
        }
    }

    subscript(index: MailClassification) -> Double {
        get {
            return confidenceLevels[index] ?? 0.0
        }
    }
}

typealias ClassificationSignalProducer = SignalProducer<MailClassificationPrediction, NoError>

class AntiSpamBot {
    let bodyModel = BodyModel()
    let subjectModel = SubjectModel()
    let attachmentModel = AttachmentModel()

    func imagePrediction(of data: Data) -> ClassificationSignalProducer {
        return SignalProducer { observer, lifetime in
            do {
                let model = try VNCoreMLModel(for: self.attachmentModel.model)
                let request = VNCoreMLRequest(model: model) { request, error in
                    guard let results = request.results else {
                        observer.send(value: .empty)
                        observer.sendCompleted()
                        return
                    }

                    let classifications = results as! [VNClassificationObservation]

                    if classifications.isEmpty {
                        observer.send(value: .empty)
                        observer.sendCompleted()
                    } else {
                        var confidence = MailClassification.variants.reduce(into: [:]) { $0[$1] = 0.0 }

                        classifications.forEach { classification in
                            confidence[MailClassification(rawValue: classification.identifier)!]? = Double(classification.confidence)
                        }

                        observer.send(value: MailClassificationPrediction(confidenceLevels: confidence))
                        observer.sendCompleted()
                    }
                }

                request.imageCropAndScaleOption = .centerCrop

                // Execute the vision request
                let handler = VNImageRequestHandler(data: data, options: [:])
                try handler.perform([request])
            } catch {
                observer.send(value: .empty)
                observer.sendCompleted()
            }
        }
    }

    func predictBasedOnAttachments(mail: MailContent) -> ClassificationSignalProducer {
        return mail.classifyableImages()
            .flatten()
            .flatMap(.merge) { self.imagePrediction(of: $0) }
            .collect()
            .map { MailClassificationPrediction(byMerging: $0) }
    }

    func predictBasedOnBody(mail: MailContent) -> ClassificationSignalProducer {
        guard let body = mail.body else {
            return SignalProducer(value: .empty)
        }

        guard let predictionLabel = try? bodyModel.prediction(text: body).label, let prediction = MailClassification(rawValue: predictionLabel) else {
            return SignalProducer(value: .empty)
        }

        return SignalProducer(value: MailClassificationPrediction(confidenceLevels: [prediction: 1.0]))
    }

    func predictBasedOnSubject(mail: MailContent) -> ClassificationSignalProducer {
        guard let subject = mail.subject else {
            return SignalProducer(value: .empty)
        }

        guard let predictionLabel = try? subjectModel.prediction(text: subject).label, let prediction = MailClassification(rawValue: predictionLabel) else {
            return SignalProducer(value: .empty)
        }

        return SignalProducer(value: MailClassificationPrediction(confidenceLevels: [prediction: 1.0]))
    }

    func predict(mail: MailContent) -> ClassificationSignalProducer {
        let predictions: [ClassificationSignalProducer] = [
            predictBasedOnSubject(mail: mail),
            predictBasedOnBody(mail: mail),
//            predictBasedOnAttachments(mail: mail),
        ]

        let weights = [0.3, 0.7] // [0.2, 0.5, 0.3]
        return SignalProducer.merge(predictions)
            .collect()
            .map { try! MailClassificationPrediction(byMerging: $0, weightedBy: weights) }
    }
}

class SpamClassificationRule: BoolRule {
    let antiSpamBot = AntiSpamBot()

    func triggers(on mail: MailContent) -> SignalProducer<Bool, NoError> {
        return antiSpamBot.predict(mail: mail).map { $0.prediction ?? .Ham == .Spam }
    }
}
