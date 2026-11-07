import pytest

pytestmark = pytest.mark.integration


def test_export_round_trip(postgres_dsn):
    from csvtidy.export import export_rows

    assert export_rows([["a", "2026-03-02"]], postgres_dsn) == 1
