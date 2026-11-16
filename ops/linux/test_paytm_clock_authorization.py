import hashlib
import os
import pathlib
import tempfile
import types
import unittest
from unittest.mock import patch
from test_paytm_clock_policy import policy

key = types.ModuleType("key")
key.__dict__.update(policy.__dict__)
exec(compile((pathlib.Path(__file__).parent / "install_paytm_clock_policy.py").read_bytes(), "policy", "exec"), key.__dict__)
exec(compile((pathlib.Path(__file__).parent / "authorize_paytm_clock_key.py").read_bytes(), "key", "exec"), key.__dict__)

class AuthorizationTests(unittest.TestCase):
    def scenario(self, case):
        with tempfile.TemporaryDirectory() as directory:
            home=pathlib.Path(directory)/"home";home.mkdir();(home/".ssh").mkdir()
            target=home/".ssh/authorized_keys";target.write_bytes(b"other-key" if case=="existing" else b"")
            program=pathlib.Path(directory)/"reader";program.write_bytes(b"reader")
            config=pathlib.Path(directory)/"config";config.write_bytes(key.POLICY.encode())
            record=types.SimpleNamespace(pw_dir=str(home),pw_uid=900,pw_gid=900,pw_shell="/bin/sh")
            temporary=home/(".ssh/.clock-key-"+"a"*32)
            if case=="temp_exists":temporary.write_bytes(key.KEY_LINE.encode())
            def native(args, timeout=10):
                if args[0].endswith("ssh-keygen"):return key.FINGERPRINT
                if args[0].endswith("passwd"):return "marketbrain-health L"
                if args[0].endswith("id"):return "900"
                if args[0].endswith("runuser") and case=="unreadable":raise RuntimeError("CLOCK_STAGE_NATIVE_FAILED")
                if args[0].endswith("sshd") and "-T" in args:
                    values=dict(key.EXPECTED);values["usepam"]="no" if case=="pam" else "yes"
                    return "\n".join(k+" "+v for k,v in values.items())
                return ""
            with patch.object(key,"HOME",home),patch.object(key,"PROGRAM",program),patch.object(key,"POLICY_PATH",config),patch.object(key.os,"geteuid",return_value=0,create=True),patch.dict(os.environ,{"SSH_CONNECTION":"192.0.2.1 4000 192.0.2.2 22"}),patch.object(key.pwd,"getpwnam",return_value=record),patch.object(key,"owned_directory"),patch.object(key,"safe_file"),patch.object(key,"run",side_effect=native),patch.object(key,"exclusive_file",side_effect=lambda p,b,m:p.write_bytes(b)):
                r=key.authorize_key(hashlib.sha256(b"reader").hexdigest(),"a"*32)
            if case=="pass":self.assertIsNone(r["failure"]);self.assertTrue(r["publicKeyReadable"]);self.assertEqual(target.read_bytes(),key.KEY_LINE.encode())
            elif case=="existing":self.assertFalse(r["keyInstalled"]);self.assertEqual(target.read_bytes(),b"other-key")
            elif case=="temp_exists":self.assertFalse(r["keyInstalled"]);self.assertTrue(temporary.exists())
            elif case=="unreadable":self.assertTrue(r["rollbackVerified"]);self.assertEqual(target.read_bytes(),b"")
            else:self.assertFalse(r["keyInstalled"]);self.assertEqual(target.read_bytes(),b"")
            self.assertFalse(r["loginTested"])
    def test_success(self):self.scenario("pass")
    def test_existing_authorization(self):self.scenario("existing")
    def test_preexisting_temporary_file(self):self.scenario("temp_exists")
    def test_unreadable_rolls_back(self):self.scenario("unreadable")
    def test_pam_prerequisite(self):self.scenario("pam")

if __name__=="__main__":unittest.main()
