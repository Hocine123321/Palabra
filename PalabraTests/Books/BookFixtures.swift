import Foundation
@testable import Palabra

/// A book source that lives in memory, so tests choose exactly what exists.
struct StubBookSource: BookContentSource {
    var catalogue: String
    var lessons: [String: String]

    func catalogueData() throws -> Data { Data(catalogue.utf8) }

    func lessonData(file: String) throws -> Data {
        guard let text = lessons[file] else { throw BookLoadError.missingFile(file) }
        return Data(text.utf8)
    }
}

enum BookFixtures {
    static let catalogue = #"""
    {
      "version": 1,
      "books": [
        { "id": "history", "subject": "history", "title": "History", "language": "en",
          "chapters": [
            { "id": "unit-1", "title": "Unit 1", "lessons": [
              { "id": "empires", "file": "lesson-empires" },
              { "id": "revolutions", "file": "lesson-revolutions" }
            ] }
          ] },
        { "id": "geography", "subject": "geography", "title": "الجغرافيا", "language": "ar",
          "chapters": [
            { "id": "unit-g", "title": "Unit G", "lessons": [ { "id": "rivers", "file": "lesson-rivers" } ] }
          ] }
      ]
    }
    """#

    /// Timeline, key point, definitions with an id, a term used in running text, a recall target.
    static let empires = #"""
    {
      "id": "empires", "version": 1, "title": "Empires",
      "pages": [
        { "id": "p1", "title": "Rise", "blocks": [
          { "type": "paragraph", "text": "Trade grew in {{markets|markets}} from [[1815|e]]." },
          { "type": "timeline", "events": [
            { "date": "1815", "title": "Congress of Vienna" },
            { "date": "1914", "title": "War", "detail": "Begins" } ] }
        ] },
        { "id": "p2", "title": "Words", "blocks": [
          { "type": "definitions", "definitions": [
            { "id": "markets", "term": "Markets", "definition": "Places where [[goods|i]] are traded." } ] }
        ] }
      ]
    }
    """#

    static let revolutions = #"""
    {
      "id": "revolutions", "title": "Revolutions",
      "pages": [ { "id": "p1", "title": "Causes", "blocks": [ { "type": "list", "ordered": true, "items": ["a", "b"] } ] } ]
    }
    """#

    /// Statistics, comparison, process, an image and a block type this app does not know.
    static let rivers = #"""
    {
      "id": "rivers", "title": "الأنهار",
      "pages": [ { "id": "p1", "title": "الطول", "blocks": [
        { "type": "stats", "stats": [ { "label": "الطول", "value": "[[6650|e]]", "unit": "كم", "note": "تقريبا" } ] },
        { "type": "comparison", "corner": "النهر", "columns": ["الطول", "المصب"], "rows": [
          { "label": "النيل", "cells": ["6650", "المتوسط"] } ] },
        { "type": "process", "steps": [ { "title": "المنبع" }, { "title": "المصب", "detail": "البحر" } ] },
        { "type": "image", "image": "map-nile", "alt": "خريطة", "caption": "النيل", "style": "map" },
        { "type": "hologram" }
      ] } ]
    }
    """#

    static var source: StubBookSource {
        StubBookSource(
            catalogue: catalogue,
            lessons: ["lesson-empires": empires, "lesson-revolutions": revolutions, "lesson-rivers": rivers]
        )
    }
}
