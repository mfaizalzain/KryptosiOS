//
//  EntrySharingTests.swift
//  KryptosTests
//
//  Covers the share envelope and the expiry status vocabulary — the two pieces
//  of logic the vault list, hero cards, and detail screen all read from.
//

import XCTest
@testable import Kryptos

@MainActor
final class EntrySharingTests: XCTestCase {

    // MARK: - Share envelope

    private func decode(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testShareEnvelopeCarriesTemplateTitleAndFields() throws {
        let json = QRPayloadBuilder.shareEnvelope(
            template: .passport,
            title: "Travel passport",
            fields: [
                VaultField(name: "Passport number", value: "A12345678"),
                VaultField(name: "Nationality", value: "MY")
            ]
        )

        let object = try decode(json)
        XCTAssertEqual(object["kryptos"] as? Int, 1)
        XCTAssertEqual(object["template"] as? String, VaultTemplate.passport.rawValue)
        XCTAssertEqual(object["title"] as? String, "Travel passport")

        let fields = try XCTUnwrap(object["fields"] as? [String: String])
        XCTAssertEqual(fields["Passport number"], "A12345678")
        XCTAssertEqual(fields["Nationality"], "MY")
    }

    /// Field names are user-editable, so two fields can legitimately share one.
    /// Building the envelope must not trap on the duplicate key.
    func testShareEnvelopeToleratesDuplicateFieldNames() throws {
        let json = QRPayloadBuilder.shareEnvelope(
            template: .note,
            title: "Scratch",
            fields: [
                VaultField(name: "Custom field", value: ""),
                VaultField(name: "Custom field", value: "kept"),
                VaultField(name: "Custom field", value: "ignored")
            ]
        )

        let fields = try XCTUnwrap(try decode(json)["fields"] as? [String: String])
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields["Custom field"], "kept", "The first non-empty value should win")
    }

    func testShareEnvelopeRoundTripsThroughQRImageGeneration() throws {
        let json = QRPayloadBuilder.shareEnvelope(
            template: .apiKey,
            title: "Staging key",
            fields: [VaultField(name: "Key", value: "abc123")]
        )
        XCTAssertNotNil(QRCode.makeImage(from: json))
    }

    // MARK: - Expiry status

    func testExpiryStatusIsNilWithoutADate() {
        XCTAssertNil(ExpiryStatus(date: nil))
    }

    func testExpiryStatusReportsExpiredForPastDates() throws {
        let reference = Date()
        let past = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: reference))
        let status = try XCTUnwrap(ExpiryStatus(date: past, referenceDate: reference))

        guard case .expired = status else { return XCTFail("Expected .expired, got \(status)") }
        XCTAssertEqual(status.label, "Expired")
        XCTAssertTrue(status.isUrgent)
    }

    func testExpiryStatusReportsSoonWithinThirtyDays() throws {
        let reference = Date()
        let soon = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 10, to: reference))
        let status = try XCTUnwrap(ExpiryStatus(date: soon, referenceDate: reference))

        guard case .soon = status else { return XCTFail("Expected .soon, got \(status)") }
        XCTAssertEqual(status.label, "Expires soon")
        XCTAssertTrue(status.isUrgent)
    }

    func testExpiryStatusIsValidBeyondThirtyDays() throws {
        let reference = Date()
        let later = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 200, to: reference))
        let status = try XCTUnwrap(ExpiryStatus(date: later, referenceDate: reference))

        guard case .valid = status else { return XCTFail("Expected .valid, got \(status)") }
        XCTAssertFalse(status.isUrgent, "Compact cards should not badge a date this far out")
    }

    // MARK: - Blank-string fallback

    func testIfBlankFallsBackForWhitespaceOnlyTitles() {
        XCTAssertEqual("   ".ifBlank("Untitled"), "Untitled")
        XCTAssertEqual("".ifBlank("Untitled"), "Untitled")
        XCTAssertEqual("Passport".ifBlank("Untitled"), "Passport")
    }
}
