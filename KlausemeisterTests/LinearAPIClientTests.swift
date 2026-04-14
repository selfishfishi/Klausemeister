import Foundation
import Testing
@testable import Klausemeister

@Test func `decodeTicketDetail maps issue fields`() async throws {
    let json = #"""
    {
      "data": {
        "issue": {
          "id": "abc-123",
          "identifier": "KLA-42",
          "title": "Example ticket",
          "url": "https://linear.app/team/issue/KLA-42/example-ticket",
          "description": "Body text",
          "state": { "id": "state-id", "name": "In Progress", "type": "started" },
          "project": { "id": "proj-id", "name": "The Inspector" },
          "attachments": { "nodes": [] }
        }
      }
    }
    """#
    let data = Data(json.utf8)

    let detail = try await decodeTicketDetail(from: data, requestedId: "abc-123")

    #expect(detail.id == "abc-123")
    #expect(detail.identifier == "KLA-42")
    #expect(detail.title == "Example ticket")
    #expect(detail.descriptionMarkdown == "Body text")
    #expect(detail.url == "https://linear.app/team/issue/KLA-42/example-ticket")
    #expect(detail.projectName == "The Inspector")
    #expect(detail.projectId == "proj-id")
    #expect(detail.status.name == "In Progress")
    #expect(detail.status.type == "started")
    #expect(detail.attachedPRs.isEmpty)
}

@Test func `decodeTicketDetail filters non-GitHub attachments and maps PR state`() async throws {
    let json = #"""
    {
      "data": {
        "issue": {
          "id": "x",
          "identifier": "KLA-9",
          "title": "t",
          "url": "u",
          "description": null,
          "state": { "id": "s", "name": "Done", "type": "completed" },
          "project": null,
          "attachments": {
            "nodes": [
              {
                "id": "att-1",
                "url": "https://github.com/selfishfishi/Klausemeister/pull/138",
                "title": "PR 138",
                "sourceType": "github",
                "metadata": { "status": "merged", "number": 138, "repo": "selfishfishi/Klausemeister" }
              },
              {
                "id": "att-2",
                "url": "https://figma.com/design/123",
                "title": "Figma mock",
                "sourceType": "figma",
                "metadata": null
              }
            ]
          }
        }
      }
    }
    """#
    let data = Data(json.utf8)

    let detail = try await decodeTicketDetail(from: data, requestedId: "x")

    #expect(detail.attachedPRs.count == 1)
    let attachment = try #require(detail.attachedPRs.first)
    #expect(attachment.id == "att-1")
    #expect(attachment.state == .merged)
    #expect(attachment.number == 138)
    #expect(attachment.repo == "selfishfishi/Klausemeister")
    #expect(attachment.title == "PR 138")
}

@Test func `decodeTicketDetail falls back to URL parsing when metadata missing`() async throws {
    let json = #"""
    {
      "data": {
        "issue": {
          "id": "x",
          "identifier": "KLA-10",
          "title": "t",
          "url": "u",
          "description": null,
          "state": { "id": "s", "name": "Backlog", "type": "backlog" },
          "project": null,
          "attachments": {
            "nodes": [
              {
                "id": "att-1",
                "url": "https://github.com/owner/repo-name/pull/42",
                "title": "PR 42",
                "sourceType": "GitHub",
                "metadata": {}
              }
            ]
          }
        }
      }
    }
    """#
    let data = Data(json.utf8)

    let detail = try await decodeTicketDetail(from: data, requestedId: "x")

    let attachment = try #require(detail.attachedPRs.first)
    #expect(attachment.state == .unknown)
    #expect(attachment.number == 42)
    #expect(attachment.repo == "owner/repo-name")
}

@Test func `decodeTicketDetail throws when issue is null`() async throws {
    let json = #"""
    { "data": { "issue": null } }
    """#
    let data = Data(json.utf8)

    await #expect(throws: LinearAPIError.issueNotFound("missing")) {
        _ = try await decodeTicketDetail(from: data, requestedId: "missing")
    }
}
