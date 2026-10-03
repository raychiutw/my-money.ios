import UIKit
import Vision
import XCTest

/// 從截圖認出畫面上的字:交易列的次要文字被合成一個 VoiceOver 元素，accessibility 看不到畫面上實際寫了什麼，
/// 用 OCR 驗證「看得到的字」(#145)。辨識結果只拿來看有沒有包含關鍵字詞，不比對標點(「・」常被認成別的點)。
enum TextRecognition {
    static func lines(in image: UIImage) throws -> [String] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
