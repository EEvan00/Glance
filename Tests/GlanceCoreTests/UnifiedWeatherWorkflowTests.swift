import Foundation
import XCTest
@testable import GlanceCore

/// Resolve the bundled workflow's actual token graph against fixed weather inputs.
/// System weather actions are the boundary; text assembly and Glance parsing stay real.
final class UnifiedWeatherWorkflowTests: XCTestCase {
    func testSingleWorkflowReturnsCurrentWeatherAndHourlyForecast() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Support/WeatherShortcuts/Glance Weather.wflow")
        let workflow = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        let actions = try XCTUnwrap(workflow["WFWorkflowActions"] as? [[String: Any]])
        let fixtures = [
            "current.Temperature": "18°C", "current.Condition": "Drizzle",
            "current.UV Index": "3", "current.Precipitation Chance": "70%",
            "today.Low": "12°C", "today.High": "22°C", "today.Location": "location",
            "location.City": "Sydney",
            "hourly.Date": "2026-10-16T14:00:00+11:00\n2026-10-16T15:00:00+11:00",
            "hourly.Precipitation Chance": "60%\n20%",
            "daily.Sunrise Time": "2026-10-16T06:10:00+11:00",
            "daily.Sunset Time": "2026-10-16T19:10:00+11:00"
        ]
        var outputs: [String: String] = [:]
        func resolve(_ token: Any?) throws -> String {
            let dictionary = try XCTUnwrap(token as? [String: Any])
            let value = try XCTUnwrap(dictionary["Value"] as? [String: Any])
            if let id = value["OutputUUID"] as? String { return try XCTUnwrap(outputs[id]) }
            let text = NSMutableString(string: try XCTUnwrap(value["string"] as? String))
            let attachments = try XCTUnwrap(value["attachmentsByRange"] as? [String: [String: Any]])
            let resolved = try attachments.map { (key, attachment) -> (NSRange, String) in
                let id = try XCTUnwrap(attachment["OutputUUID"] as? String)
                let output = try XCTUnwrap(outputs[id], "Unresolved action output: \(id)")
                return (NSRangeFromString(key), output == "hourly" ? "18°C and Rain\n19°C and Cloudy" : output)
            }.sorted { $0.0.location > $1.0.location }
            for (range, output) in resolved { text.replaceCharacters(in: range, with: output) }
            return text as String
        }
        var result: String?
        for action in actions {
            let kind = try XCTUnwrap(action["WFWorkflowActionIdentifier"] as? String)
            let parameters = try XCTUnwrap(action["WFWorkflowActionParameters"] as? [String: Any])
            let value: String
            switch kind {
            case "is.workflow.actions.comment": continue
            case "is.workflow.actions.weather.currentconditions": value = "current"
            case "is.workflow.actions.weather.forecast":
                value = parameters["WFWeatherForecastType"] as? String == "Hourly" ? "hourly" : "daily"
            case "is.workflow.actions.getitemfromlist":
                XCTAssertEqual(try resolve(parameters["WFInput"]), "daily")
                value = "today"
            case "is.workflow.actions.properties.weather.conditions", "is.workflow.actions.properties.locations":
                let input = try resolve(parameters["WFInput"])
                let property = try XCTUnwrap(parameters["WFContentItemPropertyName"] as? String)
                value = try XCTUnwrap(fixtures["\(input).\(property)"])
            case "is.workflow.actions.format.date":
                XCTAssertEqual(parameters["WFDateFormatStyle"] as? String, "ISO 8601")
                XCTAssertEqual(parameters["WFISO8601IncludeTime"] as? Bool, true)
                value = try resolve(parameters["WFDate"])
            case "is.workflow.actions.gettext": value = try resolve(parameters["WFTextActionText"])
            case "is.workflow.actions.output": result = try resolve(parameters["WFOutput"]); continue
            default: XCTFail("Unmodeled workflow action: \(kind)"); return
            }
            let id = try XCTUnwrap(parameters["UUID"] as? String)
            XCTAssertNil(outputs[id], "Duplicate action identity")
            outputs[id] = value
        }
        let snapshot = try XCTUnwrap(WeatherSnapshot.fromShortcut(try XCTUnwrap(result)))
        XCTAssertEqual(snapshot.temperature, 18)
        XCTAssertEqual(snapshot.uvIndex, 3)
        XCTAssertEqual(snapshot.precipitationChance, 70)
        XCTAssertEqual(snapshot.location, "Sydney")
        XCTAssertEqual(snapshot.low, 12)
        XCTAssertEqual(snapshot.high, 22)
        XCTAssertEqual(snapshot.hourly?.map(\.temperature), [18, 19])
        XCTAssertEqual(snapshot.hourly?.map(\.precipitationChance), [60, 20])
        XCTAssertNotNil(snapshot.sunrise)
        XCTAssertNotNil(snapshot.sunset)
        XCTAssertEqual(snapshot.shortcutVersion, 2)
    }
}
