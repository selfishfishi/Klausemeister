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
    #expect(detail.url.absoluteString == "https://linear.app/team/issue/KLA-42/example-ticket")
    #expect(detail.project?.name == "The Inspector")
    #expect(detail.project?.id == "proj-id")
    #expect(detail.status.name == "In Progress")
    #expect(detail.status.type == .started)
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
          "url": "https://linear.app/t/x",
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
    let ref = try #require(attachment.github)
    #expect(ref.number == 138)
    #expect(ref.owner == "selfishfishi")
    #expect(ref.name == "Klausemeister")
    #expect(ref.fullName == "selfishfishi/Klausemeister")
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
          "url": "https://linear.app/t/x",
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
    let ref = try #require(attachment.github)
    #expect(ref.number == 42)
    #expect(ref.fullName == "owner/repo-name")
}

@Test func `decodeTicketDetail prefers metadata over URL when both present and disagree`() async throws {
    let json = #"""
    {
      "data": {
        "issue": {
          "id": "x",
          "identifier": "KLA-11",
          "title": "t",
          "url": "https://linear.app/t/x",
          "description": null,
          "state": { "id": "s", "name": "Done", "type": "completed" },
          "project": null,
          "attachments": {
            "nodes": [
              {
                "id": "att-1",
                "url": "https://github.com/url/parsed/pull/42",
                "title": "Conflicting metadata",
                "sourceType": "github",
                "metadata": { "status": "merged", "number": 999, "repo": "metadata/wins" }
              }
            ]
          }
        }
      }
    }
    """#
    let data = Data(json.utf8)

    let detail = try await decodeTicketDetail(from: data, requestedId: "x")

    let ref = try #require(detail.attachedPRs.first?.github)
    #expect(ref.number == 999)
    #expect(ref.fullName == "metadata/wins")
}

@Test func `decodeTicketDetail maps unrecognized status type to .unknown`() async throws {
    let json = #"""
    {
      "data": {
        "issue": {
          "id": "x",
          "identifier": "KLA-12",
          "title": "t",
          "url": "https://linear.app/t/x",
          "description": null,
          "state": { "id": "s", "name": "Future", "type": "someNewLinearType" },
          "project": null,
          "attachments": { "nodes": [] }
        }
      }
    }
    """#
    let data = Data(json.utf8)

    let detail = try await decodeTicketDetail(from: data, requestedId: "x")

    #expect(detail.status.type == .unknown)
    #expect(detail.status.name == "Future")
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

@Test func `inspectorFetchError maps LinearAPIError and OAuthError to typed cases`() {
    #expect(InspectorFetchError.from(LinearAPIError.rateLimited) == .rateLimited)
    #expect(InspectorFetchError.from(LinearAPIError.issueNotFound("abc")) == .notFound(id: "abc"))
    #expect(InspectorFetchError.from(OAuthError.unauthorized) == .unauthorized)
    let transport = InspectorFetchError.from(URLError(.notConnectedToInternet))
    if case .transport = transport {
        #expect(Bool(true))
    } else {
        Issue.record("expected .transport case, got \(transport)")
    }
}
