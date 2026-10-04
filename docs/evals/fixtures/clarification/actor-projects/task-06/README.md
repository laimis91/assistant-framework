# Issue Board

Issue Board is a small synthetic tracker with a detail-page renderer, comments, project membership, and private issues.

Requests for `/issues/{issue_id}` pass through `src/issue_access.py`. Private issues are visible to their reporter and project members with private-issue access. The detail-page rendering seam is `src/issue_detail.py`. External customer links are governed by `docs/customer-link-policy.md`. Run the existing tests with `python3 -m unittest discover -s tests`.
