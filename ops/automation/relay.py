"""Small, single-spare-laptop maintenance queue. No shell execution on the relay."""
import argparse
import hashlib
import hmac
import json
import sqlite3
import ssl
import time
import uuid
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

JOBS = {"diagnostic", "intervention-test", "paytm-transport-test", "paytm-denial-recovery"}
TERMINAL = {"SUCCEEDED", "FAILED", "INTERRUPTED", "CANCELLED"}
MAX_BODY = 262144


class Queue:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.execute("CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, kind TEXT, state TEXT, created REAL, updated REAL, result TEXT)")
        self.db.execute("CREATE TABLE IF NOT EXISTS job_specs (id TEXT PRIMARY KEY, spec TEXT NOT NULL)")
        self.db.commit()

    def submit(self, body):
        reviewed = body.get("kind") in {"paytm-transport-test", "paytm-denial-recovery"}
        expected = {"id", "kind", "spec"} if reviewed else {"id", "kind"}
        if set(body) != expected or body["kind"] not in JOBS:
            raise ValueError("Unsupported job")
        spec = body.get("spec")
        if reviewed:
            if (not isinstance(spec, dict) or set(spec) != {"revision", "sha256", "mode"}
                or not re.fullmatch(r"[a-f0-9]{40}", spec.get("revision", ""))
                or not re.fullmatch(r"[A-F0-9]{64}", spec.get("sha256", ""))
                or spec.get("mode") not in ({"Observe", "Apply", "FailureFixture"} if body["kind"] == "paytm-denial-recovery" else {"Observe", "FailureFixture"})):
                raise ValueError("Invalid test specification")
        if str(uuid.UUID(body["id"])) != body["id"]:
            raise ValueError("Invalid job ID")
        old = self.get(body["id"])
        if old:
            if old["kind"] != body["kind"] or old.get("spec") != spec:
                raise ValueError("ID already belongs to another job")
            return old
        if self.db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0] >= 10000:
            raise ValueError("History capacity reached; archive before adding jobs")
        if self.db.execute("SELECT COUNT(*) FROM jobs WHERE state NOT IN ('SUCCEEDED','FAILED','INTERRUPTED','CANCELLED')").fetchone()[0] >= 20:
            raise ValueError("Queue full")
        now = time.time()
        with self.db:
            self.db.execute("INSERT INTO jobs VALUES (?,?,?,?,?,NULL)", (body["id"], body["kind"], "QUEUED", now, now))
            if spec:
                self.db.execute("INSERT INTO job_specs VALUES (?,?)", (body["id"], json.dumps(spec)))
        return self.get(body["id"])

    def get(self, job_id):
        row = self.db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        if not row:
            return None
        spec = self.db.execute("SELECT spec FROM job_specs WHERE id=?", (job_id,)).fetchone()
        return dict(zip(("id", "kind", "state", "created", "updated", "result"), row)) | {"result": json.loads(row[5]) if row[5] else None, "spec": json.loads(spec[0]) if spec else None}

    def claim(self):
        # Single worker; lost claim responses return the same active job. Never
        # lease-expire/replay a machine-changing operation automatically.
        with self.db:
            row = self.db.execute("SELECT id FROM jobs WHERE state IN ('RUNNING','WAITING_FOR_USER') ORDER BY created LIMIT 1").fetchone()
            if row:
                return self.get(row[0])
            row = self.db.execute("SELECT id FROM jobs WHERE state='QUEUED' ORDER BY created LIMIT 1").fetchone()
            if row:
                self.db.execute("UPDATE jobs SET state='RUNNING', updated=? WHERE id=?", (time.time(), row[0]))
                return self.get(row[0])
        return None

    def update(self, body):
        if set(body) != {"id", "state", "result"} or body["state"] not in TERMINAL | {"WAITING_FOR_USER", "RUNNING"}:
            raise ValueError("Invalid update")
        old = self.get(body["id"])
        if not old or old["state"] == "QUEUED":
            raise ValueError("Job was not claimed")
        if old["state"] in TERMINAL:
            if old["state"] != body["state"] or old["result"] != body["result"]:
                raise ValueError("Terminal result is immutable")
            return old
        with self.db:
            self.db.execute("UPDATE jobs SET state=?,updated=?,result=? WHERE id=?", (body["state"], time.time(), json.dumps(body["result"]), body["id"]))
        return self.get(body["id"])

    def cancel(self, body):
        old = self.get(body["id"])
        if not old or old["state"] != "QUEUED":
            raise ValueError("Only queued jobs can be cancelled; running jobs require local intervention")
        with self.db:
            self.db.execute("UPDATE jobs SET state='CANCELLED', updated=? WHERE id=?", (time.time(), body["id"]))
        return self.get(body["id"])


class Handler(BaseHTTPRequestHandler):
    def handle(self):
        try:
            super().handle()
        except (ConnectionError, ssl.SSLError, TimeoutError):
            pass  # Disconnects/pin rejection do not disclose request details.

    def log_message(self, *_):
        pass  # Never log authorization headers or report bodies.

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def do_POST(self):
        try:
            required = {"/submit": "controller", "/result": "controller", "/cancel": "controller", "/claim": "worker", "/update": "worker"}.get(self.path)
            supplied = hashlib.sha256(self.headers.get("Authorization", "").removeprefix("Bearer ").encode()).hexdigest()
            if required is None or not hmac.compare_digest(supplied, self.server.credentials[required]):
                self.reply(403, {"error": "Forbidden"})
                return
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                raise ValueError("Invalid body size")
            body = json.loads(self.rfile.read(length))
            queue = self.server.queue
            value = {"/submit": lambda: queue.submit(body), "/result": lambda: queue.get(body["id"]), "/cancel": lambda: queue.cancel(body), "/claim": queue.claim, "/update": lambda: queue.update(body)}[self.path]()
            self.reply(200, {"job": value})
        except (ValueError, KeyError, TypeError):
            self.reply(400, {"error": "Invalid request or state transition"})

    def reply(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--bind", default="127.0.0.1")
    args = parser.parse_args()
    directory = Path(args.directory)
    config = json.loads((directory / "server.json").read_text())
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(directory / "server.crt", directory / "server.key")
    server = HTTPServer((args.bind, 18443), Handler)
    server.credentials = config
    server.queue = Queue(directory / "jobs.sqlite")
    # Bound TLS handshakes too; a stalled unauthenticated client cannot hang
    # the single-worker queue indefinitely.
    original = server.get_request
    def accept():
        sock, address = original()
        sock.settimeout(10)
        return context.wrap_socket(sock, server_side=True), address
    server.get_request = accept
    server.serve_forever()


if __name__ == "__main__":
    main()
