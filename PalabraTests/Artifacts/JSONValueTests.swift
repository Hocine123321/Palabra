import XCTest
@testable import Palabra

final class JSONValueTests: XCTestCase {
    func testRoundTrip() {
        let value = JSONValue.parse(#"{"a":[1,"x",null,true],"b":{"c":2.5}}"#)!
        XCTAssertEqual(JSONValue.parse(value.jsonString), value)
    }

    func testIntValueOnlyForIntegral() {
        XCTAssertEqual(JSONValue.number(3).intValue, 3)
        XCTAssertNil(JSONValue.number(3.5).intValue)
    }

    func testBoolIsNotDecodedAsNumber() {
        XCTAssertEqual(JSONValue.parse("true"), .bool(true))
        XCTAssertEqual(JSONValue.parse("1"), .number(1))
    }

    func testSubscriptAndAccessors() {
        let value = JSONValue.parse(#"{"name":"hola","n":2,"list":[1],"flag":false}"#)!
        XCTAssertEqual(value["name"]?.stringValue, "hola")
        XCTAssertEqual(value["n"]?.intValue, 2)
        XCTAssertEqual(value["list"]?.arrayValue, [.number(1)])
        XCTAssertEqual(value["flag"]?.boolValue, false)
        XCTAssertNil(value["missing"])
        XCTAssertNil(JSONValue.string("x")["name"])
    }

    func testJSONStringIsSortedAndUnescapedSlashes() {
        let value = JSONValue.object(["b": .number(1), "a": .string("x/y")])
        XCTAssertEqual(value.jsonString, #"{"a":"x/y","b":1}"#)
    }

    func testMalformedParseIsNil() {
        XCTAssertNil(JSONValue.parse("{nope"))
    }
}
