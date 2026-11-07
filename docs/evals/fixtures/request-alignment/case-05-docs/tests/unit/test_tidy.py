from csvtidy.tidy import tidy_cell


def test_trims_whitespace():
    assert tidy_cell("  a ") == "a"


def test_unifies_dates():
    assert tidy_cell("03/02/2026") == "2026-03-02"
