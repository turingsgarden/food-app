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
    let additionalFields: [HealthOCRAdditionalField]

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
        case additionalFields = "additional_fields"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // status and fields are required by the new contract, but defaults keep
        // the app compatible with an older deployed OCR response.
        status = try container.decodeIfPresent(
            HealthOCRStatus.self,
            forKey: .status
        ) ?? .noFields

        message = try container.decodeIfPresent(String.self, forKey: .message)

        systolicBP = try container.decodeFlexibleDoubleIfPresent(forKey: .systolicBP)
        diastolicBP = try container.decodeFlexibleDoubleIfPresent(forKey: .diastolicBP)
        heightCM = try container.decodeFlexibleDoubleIfPresent(forKey: .heightCM)
        weightKG = try container.decodeFlexibleDoubleIfPresent(forKey: .weightKG)
        bmi = try container.decodeFlexibleDoubleIfPresent(forKey: .bmi)
        bloodSugar = try container.decodeFlexibleDoubleIfPresent(forKey: .bloodSugar)
        hba1c = try container.decodeFlexibleDoubleIfPresent(forKey: .hba1c)
        cholesterol = try container.decodeFlexibleDoubleIfPresent(forKey: .cholesterol)
        ldl = try container.decodeFlexibleDoubleIfPresent(forKey: .ldl)
        hdl = try container.decodeFlexibleDoubleIfPresent(forKey: .hdl)
        triglycerides = try container.decodeFlexibleDoubleIfPresent(forKey: .triglycerides)

        fields = try container.decodeIfPresent(
            HealthOCRFields.self,
            forKey: .fields
        ) ?? HealthOCRFields.empty

        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)


        additionalFields = try container.decodeIfPresent([HealthOCRAdditionalField].self, forKey: .additionalFields) ?? []

    }
}


// MARK: - Additional OCR measurement

struct HealthOCRAdditionalField: Codable, Identifiable {
    let name: String
    let value: HealthOCRRawValue?
    let unit: String?

    var id: String {
        "\(name)|\(value?.displayText ?? "")|\(unit ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case name
        case value
        case unit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        name = try container.decodeIfPresent(
            String.self,
            forKey: .name
        ) ?? "Unknown field"

        value = try container.decodeIfPresent(
            HealthOCRRawValue.self,
            forKey: .value
        )

        unit = try container.decodeIfPresent(
            String.self,
            forKey: .unit
        )
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        systolicBP = try container.decodeFieldIfPresent(
            forKey: .systolicBP,
            standardUnit: "mmHg"
        )
        diastolicBP = try container.decodeFieldIfPresent(
            forKey: .diastolicBP,
            standardUnit: "mmHg"
        )
        heightCM = try container.decodeFieldIfPresent(
            forKey: .heightCM,
            standardUnit: "cm"
        )
        weightKG = try container.decodeFieldIfPresent(
            forKey: .weightKG,
            standardUnit: "kg"
        )
        bmi = try container.decodeFieldIfPresent(
            forKey: .bmi,
            standardUnit: "kg/m²"
        )
        bloodSugar = try container.decodeFieldIfPresent(
            forKey: .bloodSugar,
            standardUnit: "mmol/L"
        )
        hba1c = try container.decodeFieldIfPresent(
            forKey: .hba1c,
            standardUnit: "%"
        )
        cholesterol = try container.decodeFieldIfPresent(
            forKey: .cholesterol,
            standardUnit: "mmol/L"
        )
        ldl = try container.decodeFieldIfPresent(
            forKey: .ldl,
            standardUnit: "mmol/L"
        )
        hdl = try container.decodeFieldIfPresent(
            forKey: .hdl,
            standardUnit: "mmol/L"
        )
        triglycerides = try container.decodeFieldIfPresent(
            forKey: .triglycerides,
            standardUnit: "mmol/L"
        )
    }

    private init(
        systolicBP: HealthOCRField,
        diastolicBP: HealthOCRField,
        heightCM: HealthOCRField,
        weightKG: HealthOCRField,
        bmi: HealthOCRField,
        bloodSugar: HealthOCRField,
        hba1c: HealthOCRField,
        cholesterol: HealthOCRField,
        ldl: HealthOCRField,
        hdl: HealthOCRField,
        triglycerides: HealthOCRField
    ) {
        self.systolicBP = systolicBP
        self.diastolicBP = diastolicBP
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.bmi = bmi
        self.bloodSugar = bloodSugar
        self.hba1c = hba1c
        self.cholesterol = cholesterol
        self.ldl = ldl
        self.hdl = hdl
        self.triglycerides = triglycerides
    }

    static let empty = HealthOCRFields(
        systolicBP: .empty(unit: "mmHg"),
        diastolicBP: .empty(unit: "mmHg"),
        heightCM: .empty(unit: "cm"),
        weightKG: .empty(unit: "kg"),
        bmi: .empty(unit: "kg/m²"),
        bloodSugar: .empty(unit: "mmol/L"),
        hba1c: .empty(unit: "%"),
        cholesterol: .empty(unit: "mmol/L"),
        ldl: .empty(unit: "mmol/L"),
        hdl: .empty(unit: "mmol/L"),
        triglycerides: .empty(unit: "mmol/L")
    )
}


// MARK: - One field's details

struct HealthOCRField: Codable {
    let raw: HealthOCRRaw
    let processed: HealthOCRProcessed
    let transform: HealthOCRTransform

    enum CodingKeys: String, CodingKey {
        case raw
        case processed
        case transform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        raw = try container.decodeIfPresent(
            HealthOCRRaw.self,
            forKey: .raw
        ) ?? .empty

        processed = try container.decodeIfPresent(
            HealthOCRProcessed.self,
            forKey: .processed
        ) ?? .empty

        transform = try container.decodeIfPresent(
            HealthOCRTransform.self,
            forKey: .transform
        ) ?? .empty
    }

    private init(
        raw: HealthOCRRaw,
        processed: HealthOCRProcessed,
        transform: HealthOCRTransform
    ) {
        self.raw = raw
        self.processed = processed
        self.transform = transform
    }

    static func empty(unit: String) -> HealthOCRField {
        HealthOCRField(
            raw: .empty,
            processed: HealthOCRProcessed(value: nil, unit: unit),
            transform: .empty
        )
    }

    func addingFallbackUnit(_ standardUnit: String) -> HealthOCRField {
        guard processed.unit.isEmpty else {
            return self
        }

        return HealthOCRField(
            raw: raw,
            processed: HealthOCRProcessed(
                value: processed.value,
                unit: standardUnit
            ),
            transform: transform
        )
    }
}


// MARK: - Raw OCR reading

struct HealthOCRRaw: Codable {
    let name: String?
    let value: HealthOCRRawValue?
    let unit: String?

    static let empty = HealthOCRRaw(
        name: nil,
        value: nil,
        unit: nil
    )
}


// MARK: - Processed normalized reading

struct HealthOCRProcessed: Codable {
    let value: Double?
    let unit: String

    enum CodingKeys: String, CodingKey {
        case value
        case unit
    }

    init(value: Double?, unit: String) {
        self.value = value
        self.unit = unit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeFlexibleDoubleIfPresent(forKey: .value)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
    }

    static let empty = HealthOCRProcessed(value: nil, unit: "")
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

    static let empty = HealthOCRTransform(
        aliasHit: nil,
        unitFactor: nil,
        reason: "missing"
    )
}


// MARK: - Flexible raw value

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


// MARK: - Decoding helpers

private extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(
        forKey key: Key
    ) throws -> Double? {
        guard contains(key) else {
            return nil
        }

        if try decodeNil(forKey: key) {
            return nil
        }

        if let number = try? decode(Double.self, forKey: key) {
            return number
        }

        if let integer = try? decode(Int.self, forKey: key) {
            return Double(integer)
        }

        if let text = try? decode(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    func decodeFieldIfPresent(
        forKey key: Key,
        standardUnit: String
    ) throws -> HealthOCRField {
        let field = try decodeIfPresent(
            HealthOCRField.self,
            forKey: key
        ) ?? .empty(unit: standardUnit)

        return field.addingFallbackUnit(standardUnit)
    }
}