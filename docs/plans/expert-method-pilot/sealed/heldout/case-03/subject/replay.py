"""Local replay of two checkout HTTP requests."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import threading


class Gateway:
    def __init__(self):
        self.lock = threading.Lock()
        self.payments = []

    def charge(self, key):
        with self.lock:
            receipt = "receipt-" + str(len(self.payments) + 1)
            self.payments.append({"checkout_key": key, "receipt": receipt, "status": "accepted"})
            return receipt


class Checkout:
    def __init__(self, gateway):
        self.gateway = gateway
        self.completed = {}
        self.cache_lock = threading.Lock()

    def post(self, key, after_lookup=None):
        with self.cache_lock:
            receipt = self.completed.get(key)
        if receipt is not None:
            return {"key": key, "receipt": receipt, "cached": True}
        if after_lookup:
            after_lookup.wait(timeout=1)
        receipt = self.gateway.charge(key)
        with self.cache_lock:
            self.completed[key] = receipt
        return {"key": key, "receipt": receipt, "cached": False}


def replay(schedule, keys):
    gateway = Gateway()
    checkout = Checkout(gateway)
    request_keys = ["order-17", "order-17" if keys == "same" else "order-18"]
    if schedule == "parallel":
        # A deterministic arrival schedule; no alteration of business state.
        barrier = threading.Barrier(2)
        with ThreadPoolExecutor(max_workers=2) as workers:
            replies = list(workers.map(lambda key: checkout.post(key, barrier), request_keys))
    else:
        replies = [checkout.post(key) for key in request_keys]
    return {
        "schedule": schedule,
        "request_keys": request_keys,
        "replies": replies,
        "gateway_attempts": len(gateway.payments),
        "gateway_payments": gateway.payments,
        "completed": checkout.completed,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schedule", choices=["parallel", "serial"], default="parallel")
    parser.add_argument("--keys", choices=["same", "distinct"], default="same")
    args = parser.parse_args()
    print(json.dumps(replay(args.schedule, args.keys), sort_keys=True))
