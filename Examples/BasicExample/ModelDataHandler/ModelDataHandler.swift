//
//  ModelDataHandler.swift
//  BasicExample-CocoaPods-Aayush
//
//  Created by Vinod Radhakrishnan on 5/22/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//

import TensorFlowLite
import Yaml

/// A result from invoking the `Interpreter`.
struct Result {
    let inferenceTime: Double
    let inferences: [Inference]
}

/// An inference from invoking the `Interpreter`.
struct Inference {
    let confidence: Float
    let label: String
}

/// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

/// This class handles all data preprocessing and makes calls to run inference on a given frame
/// by invoking the `Interpreter`. It then formats the inferences obtained and returns the top N
/// results for a successful inference.
class ModelDataHandler {
    
    // MARK: - Public Properties
    var resultCount = 1 // Number of results to report
    var numValuesPerSensorDim = 100 // Number of values per sensor-dimension (i.e. number of values of accel-x, number of values of accel-y etc.)
    var sensorDimOrdering:[String] = [] // How should data be formatted before invoking model (for ex. <-- accel_x array ---> <--- accel-y array> etc.
    var sensorDimNormalization:[Double] = [] // Normalization values used for each data dimension
    var modelSamplePeriod:Int = 20 // Sample period which was used for model training in ms

    // MARK: - Private Properties
    
    /// List of labels from the given labels file.
    private var labels: [String] = []
    
    /// TensorFlow Lite `Interpreter` object for performing inference on a given model.
    private var interpreter: Interpreter

    /// A failable initializer for `ModelDataHandler`. A new instance is created if the model and
    /// labels files are successfully loaded from the app's main bundle. Default `threadCount` is 1.
    init?(configFileName: String)
    {
        //guard let fileURL = Bundle.main.url(forResource: "model_config_activity_recognition", withExtension: "yml") else {
        guard let fileURL = Bundle.main.url(forResource: configFileName, withExtension: "") else {
            fatalError("Model configuration YAML file not found in bundle. Please add it and try again.")
        }
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let configuration = try! Yaml.load(contents)
            resultCount = configuration["num_results"].int!
            let modelInfo:FileInfo = (name:configuration["model_filename"].string!, extension:"")
            let labelInfo:FileInfo = (name:configuration["labels_filename"].string!, extension:"")
            interpreter = loadModel(modelFileInfo: modelInfo, labelsFileInfo: labelInfo ,
            configuredResultCount: resultCount)!
            
            numValuesPerSensorDim = configuration["data_format"]["num_values_per_sensor_dimenion"].int!
            for index in 0..<configuration["data_format"]["sensor_dimension_ordering"].count! {
                let sensorDim = configuration["data_format"]["sensor_dimension_ordering"][index].string!
                sensorDimOrdering.append(sensorDim)
                sensorDimNormalization.append(configuration["data_format"]["normalization_value"][index].double!)
            }
            modelSamplePeriod = configuration["data_format"]["sample_period"].int!
            labels = loadLabels(fileInfo: labelInfo)
        } catch {
            fatalError("Invalid Sig Def YAML file. Try again.")
        }
    }
    
    func predictActivity(aggregatedData:[Double]) -> (String, String) {
        
        var sensorDataBytes : [Float] = []
        
        for (_, element) in aggregatedData.enumerated() {
            sensorDataBytes.append(Float(element))
        }
        // Pass the  buffered sensor data to TensorFlow Lite to perform inference.
        let result = runModel(input: Data(buffer: UnsafeBufferPointer(start: sensorDataBytes, count: sensorDataBytes.count)))
        //Changing the text of the predictionLabel
        let predictionLabel = result!.inferences[0].label//prediction?.classLabel
        let confidenceLabel = String(describing : Int16((result!.inferences[0].confidence) * 100.0)) + "%\n"
        
        return (predictionLabel, confidenceLabel)
    }
    
    func runModel(input: Data) -> Result? {

        let interval: TimeInterval
        let outputTensor: Tensor
        do {
            // Allocate memory for the model's input `Tensor`s.
            try interpreter.allocateTensors()
            
            // Copy the sensor data to the input `Tensor`.
            try interpreter.copy(input, toInputAt: 0)
            
            // Run inference by invoking the `Interpreter`.
            let startDate = Date()
            try interpreter.invoke()
            interval = Date().timeIntervalSince(startDate) * 1000
            
            // Get the output `Tensor` to process the inference results.
            outputTensor = try interpreter.output(at: 0)
        } catch let error {
            print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
            return nil
        }
        
        let results: [Float]
        switch outputTensor.dataType {
        case .uInt8:
            guard let quantization = outputTensor.quantizationParameters else {
                print("No results returned because the quantization values for the output tensor are nil.")
                return nil
            }
            let quantizedResults = [UInt8](outputTensor.data)
            results = quantizedResults.map {
                quantization.scale * Float(Int($0) - quantization.zeroPoint)
            }
        case .float32:
            results = [Float32](unsafeData: outputTensor.data) ?? []
        default:
            print("Output tensor data type \(outputTensor.dataType) is unsupported for this example app.")
            return nil
        }
        
        // Process the results.
        let topNInferences = getTopN(results: results)
        
        // Return the inference time and inference results.
        return Result(inferenceTime: interval, inferences: topNInferences)
    }
    
    /// Returns the top N inference results sorted in descending order.
    private func getTopN(results: [Float]) -> [Inference] {
        // Create a zipped array of tuples [(labelIndex: Int, confidence: Float)].
        let zippedResults = zip(labels.indices, results)
        
        // Sort the zipped results by confidence value in descending order.
        let sortedResults = zippedResults.sorted { $0.1 > $1.1 }.prefix(resultCount)
        
        // Return the `Inference` results.
        return sortedResults.map { result in Inference(confidence: result.1, label: labels[result.0]) }
    }

    func returnSensorDimensionNormalizationValue(name:String)->Double {
        let index = sensorDimOrdering.lastIndex(of: name)
        if index != nil {
            return sensorDimNormalization[index!]
        } else {
            return 1.0
        }
    }
}
extension Array {
    /// Creates a new array from the bytes of the given unsafe data.
    ///
    /// - Warning: The array's `Element` type must be trivial in that it can be copied bit for bit
    ///     with no indirection or reference-counting operations; otherwise, copying the raw bytes in
    ///     the `unsafeData`'s buffer to a new array returns an unsafe copy.
    /// - Note: Returns `nil` if `unsafeData.count` is not a multiple of
    ///     `MemoryLayout<Element>.stride`.
    /// - Parameter unsafeData: The data containing the bytes to turn into an array.
    init?(unsafeData: Data) {
        guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
        #if swift(>=5.0)
        self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
        #else
        self = unsafeData.withUnsafeBytes {
            .init(UnsafeBufferPointer<Element>(
                start: $0,
                count: unsafeData.count / MemoryLayout<Element>.stride
            ))
        }
        #endif  // swift(>=5.0)
    }
}

func loadModel(modelFileInfo: FileInfo, labelsFileInfo: FileInfo, threadCount: Int = 1, configuredResultCount: Int = 3) -> Interpreter? {
    let modelFilename = modelFileInfo.name
    var interpreter : Interpreter
    // Construct the path to the model file.
    guard let modelPath = Bundle.main.path(
        forResource: modelFilename,
        ofType: modelFileInfo.extension
        ) else {
            print("Failed to load the model file with name: \(modelFilename).")
            return nil
    }
    
    // Specify the options for the `Interpreter`.
    var options = InterpreterOptions()
    options.threadCount = threadCount
    do {
        // Create the `Interpreter`.
        interpreter = try Interpreter(modelPath: modelPath, options: options)
    } catch let error {
        print("Failed to create the interpreter with error: \(error.localizedDescription)")
        //throw false
        return nil
    }
    return interpreter
}

/// Loads the labels from the labels file and stores them in the `labels` property.
func loadLabels(fileInfo: FileInfo) -> [String] {
    let filename = fileInfo.name
    let fileExtension = fileInfo.extension
    guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
        fatalError("Labels file not found in bundle. Please add a labels file with name " +
            "\(filename).\(fileExtension) and try again.")
    }
    do {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return contents.components(separatedBy: .newlines)
    } catch {
        fatalError("Labels file named \(filename).\(fileExtension) cannot be read. Please add a " +
            "valid labels file and try again.")
    }
}
