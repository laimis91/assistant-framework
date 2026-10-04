"""Authorization rules for the synthetic Issue Board application."""


def can_view_issue(issue, user):
    if issue["visibility"] == "public":
        return user["project_id"] == issue["project_id"]
    return (
        user["project_id"] == issue["project_id"]
        and (
            user["id"] == issue["reporter_id"]
            or "private-issue-reader" in user["roles"]
        )
    )


def can_view_comment(issue, user):
    return can_view_issue(issue, user)


def can_view_attachment(issue, user):
    return can_view_issue(issue, user)
