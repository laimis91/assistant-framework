import json
import os
import tempfile
import unittest

from notes import store


class StoreTests(unittest.TestCase):
    def test_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "notes.json")
            store.save(path, [{"id": 1, "text": "hello"}])
            self.assertEqual(store.load(path), [{"id": 1, "text": "hello"}])

    def test_rejects_other_versions(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "notes.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump({"version": 2, "notes": []}, handle)
            with self.assertRaises(ValueError):
                store.load(path)


if __name__ == "__main__":
    unittest.main()
