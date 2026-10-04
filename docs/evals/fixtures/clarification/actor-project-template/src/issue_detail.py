"""Small issue-detail rendering seam for the synthetic Issue Board."""

from html import escape

from src.issue_access import can_view_issue


def render_issue_detail(issue, user):
    if not can_view_issue(issue, user):
        raise PermissionError("user cannot view this issue")

    issue_id = escape(str(issue["id"]), quote=True)
    summary = escape(issue["summary"])
    description = escape(issue["description"])
    return (
        f'<main data-issue-id="{issue_id}">'
        f"<h1>{summary}</h1><p>{description}</p></main>"
    )
