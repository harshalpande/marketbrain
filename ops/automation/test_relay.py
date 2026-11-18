import tempfile
import unittest
import uuid
from pathlib import Path
from relay import Queue


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "jobs.sqlite"
        self.q = Queue(self.path)
        self.job = {"id": str(uuid.uuid4()), "kind": "diagnostic"}

    def tearDown(self):
        self.q.db.close()
        self.temp.cleanup()

    def test_duplicate_submission_and_lost_claim(self):
        self.q.submit(self.job)
        self.q.submit(self.job)
        first = self.q.claim()
        self.assertEqual(first, self.q.claim())
        self.assertEqual(self.q.db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0], 1)

    def test_result_retry_immutable_and_persistent(self):
        self.q.submit(self.job)
        self.q.claim()
        update = dict(id=self.job["id"], state="SUCCEEDED", result={"checks": 3})
        self.q.update(update)
        self.q.update(update)
        with self.assertRaises(ValueError):
            self.q.update(update | {"state": "FAILED"})
        self.q.db.close()
        self.q = Queue(self.path)
        self.assertEqual(self.q.get(self.job["id"])["result"], {"checks": 3})
        self.assertIsNone(self.q.claim())

    def test_intervention_and_interruption(self):
        self.q.submit(self.job)
        self.q.claim()
        self.q.update(dict(id=self.job["id"], state="WAITING_FOR_USER", result=None))
        self.assertEqual(self.q.claim()["state"], "WAITING_FOR_USER")
        self.q.update(dict(id=self.job["id"], state="INTERRUPTED", result=None))
        self.assertIsNone(self.q.claim())

    def test_catalogue_and_parameters_rejected(self):
        for job in (self.job | {"script": "anything"}, self.job | {"kind": "shell"}, self.job | {"id": "../x"}):
            with self.assertRaises(ValueError):
                self.q.submit(job)

    def test_no_result_before_claim_and_no_cancel_running(self):
        self.q.submit(self.job)
        with self.assertRaises(ValueError):
            self.q.update(dict(id=self.job["id"], state="SUCCEEDED", result=None))
        self.q.claim()
        with self.assertRaises(ValueError):
            self.q.cancel(self.job)

    def test_cancel_queued(self):
        self.q.submit(self.job)
        self.q.cancel(self.job)
        self.assertIsNone(self.q.claim())


if __name__ == "__main__":
    unittest.main()
