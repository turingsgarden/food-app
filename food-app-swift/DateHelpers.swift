//
//  DateHelpers.swift
//  food-app-swift
//
//  Created by NutriCam on 4/13/26.
//
//
//  DateHelpers.swift
//  food-app-swift
//
//  全局日期解析工具 — 支持带微秒的 ISO8601 格式
//  (2026-04-13T03:51:35.123456 等所有变体)
//

import Foundation

/// 解析带/不带微秒的 ISO8601 字符串
/// 支持：2026-04-13T03:51:35.123456 / 2026-04-13T03:51:35Z / 2026-04-13 03:51:35
func parseISO8601(_ s: String?) -> Date? {
    guard let s = s, !s.isEmpty else { return nil }

    // 1. 带小数秒（微秒）
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }

    // 2. 标准 ISO8601
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    if let d = f2.date(from: s) { return d }

    // 3. 默认 ISO8601DateFormatter
    if let d = ISO8601DateFormatter().date(from: s) { return d }

    // 4. DateFormatter 兜底
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
