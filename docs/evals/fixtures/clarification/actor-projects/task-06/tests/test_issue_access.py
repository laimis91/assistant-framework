import unittest

from src.issue_access import can_view_attachment, can_view_comment, can_view_issue


def test_private_issue_requires_project_private_issue_access():
    issue = {"project_id": "APP", "visibility": "private", "reporter_id": "u1"}
    user = {"project_id": "APP", "id": "u2", "roles": []}

    assert not can_view_issue(issue, user)


def test_project_private_issue_reader_can_view_issue_comments_and_attachments():
    issue = {"project_id": "APP", "visibility": "private", "reporter_id": "u1"}
    user = {"project_id": "APP", "id": "u2", "roles": ["private-issue-reader"]}

    assert can_view_issue(issue, user)
    assert can_view_comment(issue, user)
    assert can_view_attachment(issue, user)


def load_tests(loader, standard_tests, pattern):
    access_assertions = (
        test_private_issue_requires_project_private_issue_access,
        test_project_private_issue_reader_can_view_issue_comments_and_attachments,
    )
    standard_tests.addTests(unittest.FunctionTestCase(test) for test in access_assertions)
    return standard_tests
