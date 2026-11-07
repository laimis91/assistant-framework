import pytest


@pytest.fixture(scope="session")
def postgres_dsn():
    from testcontainers.postgres import PostgresContainer

    with PostgresContainer("postgres:16", driver=None) as container:
        yield container.get_connection_url()
