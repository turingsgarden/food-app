import Foundation

// MARK: - Complete OCR response

struct HealthOCRResponse: Codable {
    let status: HealthOCRStatus
    let message: String?

    // Flat processed values returned for convenient frontend access.
    let systolicBP: Double?
    let diastolicBP: Double?
    let heightCM: Double?
    let weightKG: Double?
    let bmi: Double?
    let bloodSugar: Double?
    let hba1c: Double?
    let cholesterol: Double?
    let ldl: Double?
    let hdl: Double?
    let triglycerides: Double?

    // Full raw + processed + transform structure.
    let fields: HealthOCRFields

    // Present only when the backend uses include_raw_text=True.
    let rawText: String?

    enum CodingKeys: String, CodingKey {
        case status
        case message

        case systolicBP = "systolic_bp"
        case diastolicBP = "diastolic_bp"
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bmi
        case bloodSugar = "blood_sugar"
        case hba1c
        case cholesterol
        case ldl
        case hdl
        case triglycerides

        case fields
        case rawText = "raw_text"
    }
}


// MARK: - OCR status

enum HealthOCRStatus: String, Codable {
    case ok
    case noFields = "no_fields"
    case noText = "no_text"
}


// MARK: - All 11 field details

struct HealthOCRFields: Codable {
    let systolicBP: HealthOCRField
    let diastolicBP: HealthOCRField
    let heightCM: HealthOCRField
    let weightKG: HealthOCRField
    let bmi: HealthOCRField
    let bloodSugar: HealthOCRField
    let hba1c: HealthOCRField
    let cholesterol: HealthOCRField
    let ldl: HealthOCRField
    let hdl: HealthOCRField
    let triglycerides: HealthOCRField

    enum CodingKeys: String, CodingKey {
        case systolicBP = "systolic_bp"
        case diastolicBP = "diastolic_bp"
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bmi
        case bloodSugar = "blood_sugar"
        case hba1c
        case cholesterol
        case ldl
        case hdl
        case triglycerides
    }
}


// MARK: - One field's details

struct HealthOCRField: Codable {
    let raw: HealthOCRRaw
    let processed: HealthOCRProcessed
    let transform: HealthOCRTransform
}


// MARK: - Raw OCR reading

struct HealthOCRRaw: Codable {
    let name: String?
    let value: HealthOCRRawValue?
    let unit: String?
}


// MARK: - Processed normalized reading

struct HealthOCRProcessed: Codable {
    let value: Double?
    let unit: String
}


// MARK: - Transformation information

struct HealthOCRTransform: Codable {
    let aliasHit: String?
    let unitFactor: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case aliasHit = "alias_hit"
        case unitFactor = "unit_factor"
        case reason
    }
}


// MARK: - Flexible raw value
//
// The Python response may return raw.value as either:
// "64.33"        String
// 64.33          Number
// null           nil
//
// A normal String? or Double? property cannot handle both formats.

enum HealthOCRRawValue: Codable {
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        throw DecodingError.typeMismatch(
            HealthOCRRawValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a string or numeric OCR value."
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)

        case .number(let value):
            try container.encode(value)
        }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            return value

        case .number(let value):
            return value.formatted()
        }
    }
}