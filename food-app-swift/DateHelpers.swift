//
//  DateHelpers.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/13/26.


import Foundation


func parseISO8601(_ s: String?) -> Date? {
    guard let s = s, !s.isEmpty else { return nil }


    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }


    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    if let d = f2.date(from: s) { return d }


    if let d = ISO8601DateFormatter().date(from: s) { return d }


    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    for fmt in [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss"
    ] {
        df.dateFormat = fmt
        if let d = df.date(from: s) { return d }
    }
    return nil
}
