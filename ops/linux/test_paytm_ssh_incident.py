import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("incident", Path(__file__).with_name("CollectPaytmSshIncident.py"))
incident = importlib.util.module_from_spec(spec)
spec.loader.exec_module(incident)


def row(pid, message):
    return {"_PID": str(pid), "MESSAGE": message, "__REALTIME_TIMESTAMP": "1794576742000000"}


class IncidentTests(unittest.TestCase):
    def test_connection_grouping_and_redaction(self):
        result = incident.summarize([
            row(7, "Accepted publickey for marketbrain-gateway from 49.36.40.116 port 62891 ssh2 SECRET"),
            row(7, "Received disconnect from 49.36.40.116 port 62891: SECRET"),
            row(8, "Failed password for root from 1.2.3.4 port 222 SECRET"),
        ])
        self.assertEqual([x["kind"] for x in result["events"]], ["GATEWAY_KEY_ACCEPTED", "DISCONNECTED"])
        self.assertEqual(result["events"][0]["clientPort"], 62891)
        self.assertNotIn("SECRET", json.dumps(result))
        self.assertNotIn("1.2.3.4", json.dumps(result))

    def test_throttling_not_assigned_to_gateway(self):
        result = incident.summarize([row(1, "drop connection #11 from SECRET past MaxStartups")])
        self.assertEqual(result["throttleOrPenaltyEventCount"], 1)
        self.assertFalse(result["events"][0]["gatewayPidRelated"])

    def test_session_close_and_forward_denied(self):
        result = incident.summarize([row(2, "session opened for user marketbrain-gateway"),
                                    row(2, "forwarding administratively prohibited"),
                                    row(2, "session closed")])
        self.assertEqual([x["kind"] for x in result["events"]], ["SESSION_OPENED", "FORWARD_DENIED", "SESSION_CLOSED"])

    def collect_result(self, output, code=0):
        with patch.object(incident.subprocess, "run", return_value=subprocess.CompletedProcess([], code, output, "SECRET")) as run:
            result = incident.collect()
            self.assertEqual(run.call_args.kwargs["timeout"], 20)
            return result

    def test_empty_is_not_pass(self):
        self.assertFalse(self.collect_result("")["success"])

    def test_truncated_is_not_pass(self):
        self.assertTrue(self.collect_result((json.dumps(row(1, "other")) + "\n") * 2001)["possiblyTruncated"])

    def test_malformed_is_not_pass(self):
        self.assertFalse(self.collect_result("not json")["success"])

    def test_nonzero_is_not_pass(self):
        self.assertFalse(self.collect_result("", 1)["success"])

    def test_timeout_is_captured(self):
        with patch.object(incident.subprocess, "run", side_effect=subprocess.TimeoutExpired("journalctl", 20)):
            self.assertEqual(incident.collect()["failureType"], "TimeoutExpired")

    def test_success_does_not_claim_cause_or_clock(self):
        result = self.collect_result(json.dumps(row(2, "Accepted publickey for marketbrain-gateway")))
        self.assertTrue(result["success"])
        self.assertFalse(result["historicalCauseEstablished"])
        self.assertFalse(result["clockSynchronizationVerified"])


if __name__ == "__main__":
    unittest.main()
