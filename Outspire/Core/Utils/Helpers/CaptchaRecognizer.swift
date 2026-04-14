import CoreImage
import Foundation
import Vision

class CaptchaRecognizer {
    enum RecognitionMethod {
        case basic
        case contrastEnhanced
        case binarized
        case combined // Tries all methods
    }

    static func recognizeText(
        in imageData: Data,
        method: RecognitionMethod = .combined,
        completion: @escaping (String?) -> Void
    ) {
        guard let cgImage = createCGImage(from: imageData) else {
            completion(nil)
            return
        }

        switch method {
        case .basic:
            performRecognition(on: cgImage, completion: completion)
        case .contrastEnhanced:
            let processed = enhanceContrast(image: cgImage)
            performRecognition(on: processed, completion: completion)
        case .binarized:
            let processed = binarizeImage(image: cgImage)
            performRecognition(on: processed, completion: completion)
        case .combined:
            // Try all methods and combine results for best accuracy
            var results: [String] = []
            let group = DispatchGroup()

            // Original image
            group.enter()
            performRecognition(on: cgImage) { result in
                if let text = result { results.append(text) }
                group.leave()
            }

            // Contrast enhanced
            group.enter()
            let contrastImage = enhanceContrast(image: cgImage)
            performRecognition(on: contrastImage) { result in
                if let text = result { results.append(text) }
                group.leave()
            }

            // Binarized
            group.enter()
            let binaryImage = binarizeImage(image: cgImage)
            performRecognition(on: binaryImage) { result in
                if let text = result { results.append(text) }
                group.leave()
            }

            // Scale 2x
            group.enter()
            if let scaledImage = scaleImage(cgImage, by: 2.0) {
                performRecognition(on: scaledImage) { result in
                    if let text = result { results.append(text) }
                    group.leave()
                }
            } else {
                group.leave()
            }

            group.notify(queue: .main) {
                // Find most common result or longest valid result
                let bestGuess = findBestResult(from: results)
                completion(bestGuess)
            }
        }
    }

    private static func createCGImage(from data: Data) -> CGImage? {
        if let provider = CGDataProvider(data: data as CFData) {
            return CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ) ?? CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        }

        // Alternative approach using Core Image
        let ciImage = CIImage(data: data)
        if let ciImage {
            let context = CIContext()
            return context.createCGImage(ciImage, from: ciImage.extent)
        }

        return nil
    }

    private static func performRecognition(on cgImage: CGImage, completion: @escaping (String?) -> Void) {
        // Create a request handler
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Create text recognition request with specialized settings for captchas
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation]
            else {
                completion(nil)
                return
            }

            // Extract and process text
            let recognizedStrings = observations.compactMap { observation -> String? in
                // Get multiple candidates to improve chances
                let candidates = observation.topCandidates(5)
                return candidates.first?.string
            }

            // Join and filter text
            let text = recognizedStrings.joined()

            // Filter to likely captcha characters (alphanumeric)
            let filteredText = text.filter { $0.isLetter || $0.isNumber }

            // Most captchas are 4-6 characters
            let captchaText = String(filteredText.prefix(6))

            completion(captchaText.isEmpty ? nil : captchaText)
        }

        // Configure for captcha recognition
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"] // Focus on English characters
        request.usesLanguageCorrection = false // Disable language correction (important for captchas)
        request
            .customWords = [
                "abcdefghijklmnopqrstuvwxyz",
                "ABCDEFGHIJKLMNOPQRSTUVXWYZ",
                "0123456789"
            ] // Common captcha chars

        // Perform the request
        try? requestHandler.perform([request])
    }

    // MARK: - Image Processing Methods

    private static func enhanceContrast(image: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: image)

        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(1.5, forKey: kCIInputContrastKey) // Increase contrast
        filter.setValue(0.0, forKey: kCIInputSaturationKey) // Remove color
        filter.setValue(0.1, forKey: kCIInputBrightnessKey) // Slightly brighten

        if let outputImage = filter.outputImage {
            let context = CIContext()
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return cgImage
            }
        }

        return image
    }

    private static func binarizeImage(image: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: image)

        // First convert to grayscale
        let grayFilter = CIFilter(name: "CIColorControls")!
        grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayFilter.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let grayImage = grayFilter.outputImage else { return image }

        // Then threshold to create binary image
        let thresholdFilter = CIFilter(name: "CIColorThreshold")!
        thresholdFilter.setValue(grayImage, forKey: kCIInputImageKey)
        thresholdFilter.setValue(0.5, forKey: "inputThreshold")

        if let outputImage = thresholdFilter.outputImage {
            let context = CIContext()
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return cgImage
            }
        }

        return image
    }

    private static func scaleImage(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    private static func findBestResult(from results: [String]) -> String? {
        guard !results.isEmpty else { return nil }

        // Filter for 4 character result
        let validResults = results.filter {
            let filtered = $0.filter { $0.isLetter || $0.isNumber }
            return filtered.count == 4
        }

        if !validResults.isEmpty {
            // 1. Try to find the most common result first
            let counts = Dictionary(validResults.map { ($0, 1) }, uniquingKeysWith: +)
            if let (mostCommon, count) = counts.max(by: { $0.1 < $1.1 }), count > 1 {
                return mostCommon
            }

            // 2. If no consensus, return the first valid result
            return validResults.first
        }

        // 3. Fall back to any reasonable result
        return results.compactMap { result -> String? in
            let filtered = result.filter { $0.isLetter || $0.isNumber }
            return filtered.isEmpty ? nil : String(filtered.prefix(4))
        }.first
    }
}
