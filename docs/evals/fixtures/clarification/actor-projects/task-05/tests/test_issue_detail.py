import unittest

from src.issue_detail import render_issue_detail


class IssueDetailTests(unittest.TestCase):
    def setUp(self):
        self.issue = {
            "id": "APP-12",
            "project_id": "APP",
            "visibility": "private",
            "reporter_id": "u1",
            "summary": "Search times out",
            "description": "Search stops after ten seconds.",
        }
        self.reporter = {"project_id": "APP", "id": "u1", "roles": []}
        self.other_user = {"project_id": "APP", "id": "u2", "roles": []}

    def test_renders_issue_summary_and_description_for_reporter(self):
        rendered = render_issue_detail(self.issue, self.reporter)

        self.assertIn("Search times out", rendered)
        self.assertIn("Search stops after ten seconds.", rendered)

    def test_denies_detail_render_for_user_without_issue_access(self):
        with self.assertRaises(PermissionError):
            render_issue_detail(self.issue, self.other_user)


if __name__ == "__main__":
    unittest.main()
