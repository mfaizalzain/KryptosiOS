//
//  QRPayloadBuilderTests.swift
//  KryptosTests
//
//  Created by Faizal Zain on 07/08/2026.
//

import XCTest
@testable import Kryptos

@MainActor
final class QRPayloadBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func payloadData(for type: QRPayloadType, _ fields: [String: String]) -> String {
        var vaultFields = fields.map { VaultField(name: $0.key, value: $0.value) }
        vaultFields.insert(VaultField(name: QRPayloadBuilder.typeField, value: type.label), at: 0)
        let generated = QRPayloadBuilder.fieldsWithGeneratedData(vaultFields)
        return generated.first { $0.name == QRPayloadBuilder.dataField }?.value ?? ""
    }

    // MARK: - Basic types

    func testTextPayloadIsRawData() {
        let result = payloadData(for: .text, ["Data": "hello world"])
        XCTAssertEqual(result, "hello world")
    }

    func testPhonePayloadUsesTelScheme() {
        let result = payloadData(for: .phone, ["Phone": "+60123456789"])
        XCTAssertEqual(result, "tel:+60123456789")
    }

    // MARK: - vCard

    func testVCardIncludesAllPopulatedFieldsInOrder() {
        let result = payloadData(for: .contact, [
            "Full name": "Faizal Zain",
            "Phone": "+60123456789",
            "Email": "faizal@example.com",
            "Organization": "Acme",
            "Job title": "Engineer",
            "Website": "https://example.com",
            "Address": "1 Jalan Bukit",
            "Note": "colleague",
        ])
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "BEGIN:VCARD")
        XCTAssertTrue(lines.contains("VERSION:3.0"))
        XCTAssertTrue(lines.contains("FN:Faizal Zain"))
        XCTAssertTrue(lines.contains("TEL:+60123456789"))
        XCTAssertTrue(lines.contains("EMAIL:faizal@example.com"))
        XCTAssertTrue(lines.contains("ORG:Acme"))
        XCTAssertTrue(lines.contains("TITLE:Engineer"))
        XCTAssertTrue(lines.contains("URL:https://example.com"))
        XCTAssertTrue(lines.contains("ADR:;;1 Jalan Bukit;;;;"))
        XCTAssertTrue(lines.contains("NOTE:colleague"))
        XCTAssertEqual(lines.last, "END:VCARD")
    }

    func testVCardSkipsBlankFields() {
        let result = payloadData(for: .contact, ["Full name": "Only Name", "Email": ""])
        XCTAssertTrue(result.contains("FN:Only Name"))
        XCTAssertFalse(result.contains("EMAIL:"))
        XCTAssertFalse(result.contains("TEL:"))
    }

    func testVCardEscapesSemicolonsAndNewlines() {
        let result = payloadData(for: .contact, ["Full name": "Doe, John", "Note": "line1\nline2"])
        XCTAssertTrue(result.contains("FN:Doe\\, John"))
        XCTAssertTrue(result.contains("NOTE:line1\\nline2"))
    }

    // MARK: - Wi-Fi

    func testWifiPayloadWithWPA2AndPassword() {
        let result = payloadData(for: .wifi, ["Network name": "HomeNet", "Security": "WPA2", "Password": "secret;123"])
        XCTAssertEqual(result, "WIFI:T:WPA2;S:HomeNet;P:secret\\;123;;")
    }

    func testWifiPayloadWithoutPasswordUsesNopass() {
        let result = payloadData(for: .wifi, ["Network name": "OpenNet", "Security": ""])
        XCTAssertEqual(result, "WIFI:T:nopass;S:OpenNet;;")
    }

    func testWifiPayloadMarksHiddenNetwork() {
        let result = payloadData(for: .wifi, ["Network name": "Hidden", "Security": "WPA", "Password": "pw", "Hidden": "true"])
        XCTAssertTrue(result.contains("H:true;"))
    }

    // MARK: - Email / SMS

    func testEmailPayloadWithSubjectAndBody() {
        let result = payloadData(for: .email, ["Email": "a@b.com", "Subject": "Hi there", "Body": "See you"])
        XCTAssertEqual(result, "mailto:a@b.com?subject=Hi%20there&body=See%20you")
    }

    func testSmsPayloadWithBody() {
        let result = payloadData(for: .sms, ["Phone": "12345", "Message": "Hello"])
        XCTAssertEqual(result, "sms:12345?body=Hello")
    }

    func testSmsPayloadWithoutBody() {
        let result = payloadData(for: .sms, ["Phone": "12345", "Message": ""])
        XCTAssertEqual(result, "sms:12345")
    }

    // MARK: - Location

    func testGeoPayloadWithoutLabel() {
        let result = payloadData(for: .location, ["Latitude": "3.1390", "Longitude": "101.6869"])
        XCTAssertEqual(result, "geo:3.1390,101.6869")
    }

    func testGeoPayloadWithLabelUsesQueryForm() {
        let result = payloadData(for: .location, ["Latitude": "3.1390", "Longitude": "101.6869", "Label": "KLCC"])
        XCTAssertEqual(result, "geo:3.1390,101.6869?q=3.1390,101.6869(KLCC)")
    }

    // MARK: - Calendar

    func testCalendarPayloadRendersVCalendarWithNormalizedDates() {
        let result = payloadData(for: .calendar, [
            "Title": "Meeting",
            "Starts": "2026-08-10 09:00",
            "Ends": "2026-08-10 10:00",
            "Location": "Room 4",
        ])
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "BEGIN:VCALENDAR")
        XCTAssertTrue(lines.contains("VERSION:2.0"))
        XCTAssertTrue(lines.contains("BEGIN:VEVENT"))
        XCTAssertTrue(lines.contains("SUMMARY:Meeting"))
        XCTAssertTrue(lines.contains("DTSTART:20260810T0900"))
        XCTAssertTrue(lines.contains("DTEND:20260810T1000"))
        XCTAssertTrue(lines.contains("LOCATION:Room 4"))
        XCTAssertTrue(lines.contains("END:VEVENT"))
        XCTAssertEqual(lines.last, "END:VCALENDAR")
    }

    // MARK: - Payment

    func testPaymentPayloadWithSchemePassesThroughUntouched() {
        let result = payloadData(for: .payment, ["URI or address": "iban:DE89370400440532013000", "Amount": "100"])
        XCTAssertEqual(result, "iban:DE89370400440532013000")
    }

    func testPaymentPayloadAppendsParamsToBareAddress() {
        let result = payloadData(for: .payment, ["URI or address": "1234567890", "Amount": "100", "Note": "rent"])
        XCTAssertEqual(result, "1234567890?amount=100&message=rent")
    }

    // MARK: - Default fields / selected type

    func testDefaultFieldsForWifiHaveSecurityPreset() {
        let fields = QRPayloadBuilder.defaultFields(for: .wifi)
        let security = fields.first { $0.name == "Security" }?.value
        XCTAssertEqual(security, "WPA")
    }

    func testSelectedTypeFallsBackToTextForUnknown() {
        let fields = [VaultField(name: QRPayloadBuilder.typeField, value: "NotAType")]
        XCTAssertEqual(QRPayloadBuilder.selectedType(from: fields), .text)
    }

    func testSelectedTypeMatchesByLabelCaseInsensitively() {
        let fields = [VaultField(name: QRPayloadBuilder.typeField, value: "wi-fi")]
        XCTAssertEqual(QRPayloadBuilder.selectedType(from: fields), .wifi)
    }

    func testFieldsWithGeneratedDataInsertsTypeFieldWhenMissing() {
        let input = [VaultField(name: "Data", value: "")]
        let result = QRPayloadBuilder.fieldsWithGeneratedData(input)
        XCTAssertTrue(result.contains { $0.name == QRPayloadBuilder.typeField })
    }
}
