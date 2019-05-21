//
//  main.swift
//  AntiSpamBotTrainer
//
//  Created by Til Blechschmidt on 18.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import CreateML

let labelledFolder = URL(fileURLWithPath: "/Users/themegatb/Downloads/spamDL/labelled")
let mlModelPath = URL(fileURLWithPath: "/Users/themegatb/Downloads")

func trainClassifier(on folder: URL) throws -> MLTextClassifier {
    let dataSource: MLTextClassifier.DataSource = .labeledDirectories(at: folder)

    let classifier = try MLTextClassifier(trainingData: dataSource)

    let trainingAccuracy = (1.0 - classifier.trainingMetrics.classificationError) * 100
    let validationAccuracy = (1.0 - classifier.validationMetrics.classificationError) * 100

    print("Accuracy on training data:\t\t", trainingAccuracy)
    print("Accuracy on validation data:\t", validationAccuracy)

    return classifier
}

let subjectClassifier = try! trainClassifier(on: labelledFolder.appendingPathComponent("Subject"))
let bodyClassifier = try! trainClassifier(on: labelledFolder.appendingPathComponent("Body"))

let classifierMetadata = MLModelMetadata(
    author: "Til Blechschmidt",
    shortDescription: "A model trained to classify emails as spam/ham",
    version: "1.0"
)

try bodyClassifier.write(to: mlModelPath.appendingPathComponent("BodyModel.mlmodel"), metadata: classifierMetadata)
try subjectClassifier.write(to: mlModelPath.appendingPathComponent("SubjectModel.mlmodel"), metadata: classifierMetadata)
