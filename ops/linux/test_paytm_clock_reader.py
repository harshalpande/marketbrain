import importlib.util
import pathlib
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).parent

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

reader = load("paytm_clock_reader")
if "pwd" not in sys.modules:
    try:
        import pwd
    except ImportError:
        sys.modules["pwd"] = types.SimpleNamespace(getpwnam=lambda n: None)
stager = load("stage_paytm_clock_reader")

class ReaderTests(unittest.TestCase):
    def test_exact_command_and_fixed_process(self):
        def run(args, **kw):
            self.assertEqual(args[0], "/usr/bin/timedatectl")
            self.assertNotIn("shell", kw)
            self.assertEqual(kw["timeout"], 2)
            return types.SimpleNamespace(returncode=0, stdout="yes\n")
        self.assertEqual(reader.read_clock("marketbrain-clock " + "a"*32, run, lambda: 1700000000000000000), "MB_CLOCK_V1|"+"a"*32+"|1700000000000|yes")
    def test_denied_inputs_never_execute(self):
        for command in ("", "id", "marketbrain-clock "+"A"*32, "marketbrain-clock "+"a"*32+";id", "marketbrain-clock "+"a"*32+"\n", "marketbrain-clock "+"a"*33):
            with self.subTest(command=command), self.assertRaises(ValueError):
                reader.read_clock(command, lambda *a, **k: self.fail("Executed invalid command"))
    def test_bad_sync(self):
        with self.assertRaises(ValueError):
            reader.read_clock("marketbrain-clock "+"a"*32, lambda *a, **k: types.SimpleNamespace(returncode=0, stdout="unknown"))
    def test_timeout(self):
        with self.assertRaises(TimeoutError):
            reader.read_clock("marketbrain-clock "+"a"*32, lambda *a, **k: (_ for _ in ()).throw(TimeoutError()))

class StageTests(unittest.TestCase):
    def scenario(self, existing=False, denial_bad=False):
        import base64, hashlib
        with tempfile.TemporaryDirectory() as directory:
            home=pathlib.Path(directory)/"home";program=pathlib.Path(directory)/"program";created=[]
            record=types.SimpleNamespace(pw_dir=str(home),pw_shell="/bin/sh",pw_uid=900,pw_gid=900)
            def getuser(n):
                if existing or created: return record
                raise KeyError(n)
            def run(args, timeout=10):
                if args[0].endswith("ssh-keygen"):return "3072 "+stager.FINGERPRINT+" (RSA)"
                if args[0].endswith("useradd"):created.append(True);return ""
                if args[0].endswith("id"):return "900"
                if args[0].endswith("passwd"):return stager.NAME+" L"
                if args[0].endswith("runuser"):return "MB_CLOCK_V1|"+"a"*32+"|1700000000000|yes"
                self.fail("Unexpected process")
            payload=b"fixture"
            with patch.object(stager,"HOME",home),patch.object(stager,"PROGRAM",program),patch.object(stager.os,"geteuid",return_value=0,create=True),patch.object(stager.pwd,"getpwnam",side_effect=getuser),patch.object(stager,"owned_directory"),patch.object(stager.os,"access",return_value=True),patch.object(stager,"run",side_effect=run),patch.object(stager,"exclusive_file",side_effect=lambda p,b,m:p.write_bytes(b)),patch.object(stager.subprocess,"run",return_value=types.SimpleNamespace(returncode=0 if denial_bad else 1,stdout="")):
                result=stager.stage(base64.b64encode(payload).decode(),hashlib.sha256(payload).hexdigest(),"a"*32)
            return result,created
    def test_success_keyless(self):
        r,c=self.scenario();self.assertTrue(c);self.assertTrue(r["keylessVerified"]);self.assertFalse(r["sshAccessEnabled"]);self.assertEqual(r["failure"],None)
    def test_existing_identity_not_mutated(self):
        r,c=self.scenario(existing=True);self.assertFalse(c);self.assertEqual(r["failure"],"CLOCK_STAGE_ACCOUNT_EXISTS")
    def test_failed_selfcheck_not_accepted(self):
        r,c=self.scenario(denial_bad=True);self.assertTrue(c);self.assertEqual(r["status"],"REVIEW_REQUIRED")

if __name__ == "__main__": unittest.main()
