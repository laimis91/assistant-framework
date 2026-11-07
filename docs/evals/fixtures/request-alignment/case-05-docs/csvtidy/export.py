"""Export tidied rows to PostgreSQL."""


def export_rows(rows, dsn):
    """Insert rows into the tidy_rows table and return the number inserted."""
    import psycopg

    with psycopg.connect(dsn) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "CREATE TABLE IF NOT EXISTS tidy_rows (id serial PRIMARY KEY, cells text[])"
            )
            for row in rows:
                cursor.execute("INSERT INTO tidy_rows (cells) VALUES (%s)", (row,))
    return len(rows)
