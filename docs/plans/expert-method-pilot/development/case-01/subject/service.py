"""Small export request path with a background-refresh admission slot."""
import argparse
import json
import threading
import time


class DatabaseTimeout(Exception):
    pass


def run(hold_ms, db_delay_ms, timeout_ms, trace):
    admission = threading.Lock()
    held = threading.Event()
    events = []
    queries = []

    def refresh():
        with admission:
            held.set()
            time.sleep(hold_ms / 1000)

    background = threading.Thread(target=refresh)
    background.start()
    held.wait(timeout=1)
    start = time.monotonic()
    acquired = admission.acquire(timeout=timeout_ms / 1000)
    waited = (time.monotonic() - start) * 1000
    events.append({"stage": "admission", "acquired": acquired, "wait_ms": round(waited, 2)})
    status = "ok"
    error = None
    try:
        if not acquired:
            # Public exception kept for compatibility with the database wrapper.
            raise DatabaseTimeout("database operation exceeded request deadline")
        queries.append("select export_rows")
        time.sleep(db_delay_ms / 1000)
        events.append({"stage": "database", "elapsed_ms": db_delay_ms})
        if db_delay_ms > timeout_ms:
            raise DatabaseTimeout("database operation exceeded request deadline")
    except DatabaseTimeout as exc:
        status, error = "failed", type(exc).__name__ + ": " + str(exc)
    finally:
        if acquired:
            admission.release()
        background.join(timeout=1)
    result = {"request": "GET /exports", "status": status, "error": error}
    if trace:
        result.update(events=events, database_queries_started=len(queries))
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh-hold-ms", type=float, default=120)
    parser.add_argument("--db-delay-ms", type=float, default=5)
    parser.add_argument("--timeout-ms", type=float, default=50)
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()
    values = [args.refresh_hold_ms, args.db_delay_ms, args.timeout_ms]
    if any(value < 0 or value > 1000 for value in values):
        parser.error("timings must be between 0 and 1000 milliseconds")
    run(*values, args.trace)
