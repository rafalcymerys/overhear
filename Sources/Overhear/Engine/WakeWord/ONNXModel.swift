import Foundation
import OnnxRuntimeBindings

/// A single ONNX graph with one float input and one float output.
///
/// Input and output names are read off the session rather than hardcoded: the
/// wake word heads were exported individually and their tensor names differ
/// from model to model (`onnx::Flatten_0` in alexa, `x.1` in hey_jarvis), so a
/// hardcoded name would work for one built-in word and fail on the next.
final class ONNXModel {
    struct Output {
        var values: [Float]
        var shape: [Int]
    }

    private let session: ORTSession
    private let inputName: String
    private let outputName: String

    init(path: String, env: ORTEnv) throws {
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(1)
        session = try ORTSession(env: env, modelPath: path, sessionOptions: options)

        guard let input = try session.inputNames().first,
              let output = try session.outputNames().first else {
            throw EngineError.modelInvalid(path)
        }
        inputName = input
        outputName = output
    }

    func run(_ values: [Float], shape: [Int]) throws -> Output {
        let data = values.withUnsafeBufferPointer {
            NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.stride)
        }
        let input = try ORTValue(
            tensorData: data,
            elementType: .float,
            shape: shape.map { NSNumber(value: $0) }
        )

        let outputs = try session.run(
            withInputs: [inputName: input],
            outputNames: [outputName],
            runOptions: nil
        )
        guard let result = outputs[outputName] else {
            throw EngineError.modelInvalid(outputName)
        }

        let resultData = try result.tensorData() as Data
        let info = try result.tensorTypeAndShapeInfo()
        return Output(
            values: resultData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) },
            shape: info.shape.map { $0.intValue }
        )
    }
}
