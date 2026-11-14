import hashlib
import os
import pathlib
import tempfile
import types
import unittest
from unittest.mock import patch
from test_paytm_clock_reader import stager

# Same composition as the remote reviewed payload.
policy = types.ModuleType("policy")
policy.__dict__.update(stager.__dict__)
exec(compile((pathlib.Path(__file__).parent / "install_paytm_clock_policy.py").read_bytes(), "policy", "exec"), policy.__dict__)

class PolicyTests(unittest.TestCase):
    def scenario(self, case):
        with tempfile.TemporaryDirectory() as directory:
            home=pathlib.Path(directory)/"home";home.mkdir();(home/".ssh").mkdir();(home/".ssh/authorized_keys").write_bytes(b"")
            program=pathlib.Path(directory)/"reader";program.write_bytes(b"reader")
            target=pathlib.Path(directory)/"policy";calls=[]
            record=types.SimpleNamespace(pw_dir=str(home),pw_uid=900,pw_shell="/bin/sh")
            if case=="exists":target.write_bytes(b"unrelated")
            def native(args, timeout=10):
                calls.append(args)
                if args[0].endswith("ssh-keygen"):return policy.FINGERPRINT
                if args[0].endswith("passwd"):return "marketbrain-health L"
                if args[0].endswith("sshd") and "-T" in args:
                    user=args[-1].split(",")[0].split("=")[1]
                    if user=="marketbrain-health":
                        values=dict(policy.EXPECTED)
                        if case=="mismatch":values["disableforwarding"]="no"
                        return "\n".join(k+" "+v for k,v in values.items())
                    if case=="otherdrift" and target.exists():return "passwordauthentication no"
                    return "passwordauthentication yes"
                if case=="reloadfail" and "reload" in args and target.exists():raise RuntimeError("CLOCK_STAGE_NATIVE_FAILED")
                return ""
            with patch.object(policy,"HOME",home),patch.object(policy,"PROGRAM",program),patch.object(policy,"POLICY_PATH",target),patch.object(policy.os,"geteuid",return_value=0,create=True),patch.dict(os.environ,{"SSH_CONNECTION":"192.0.2.1 4000 192.0.2.2 22"}),patch.object(policy.pwd,"getpwnam",return_value=record),patch.object(policy,"owned_directory"),patch.object(policy,"safe_file"),patch.object(policy,"run",side_effect=native),patch.object(policy,"exclusive_file",side_effect=lambda p,b,m:p.write_bytes(b)):
                r=policy.install_policy(hashlib.sha256(b"reader").hexdigest(),"a"*32)
            if case=="pass":
                self.assertEqual(r["status"],"CLOCK_SSH_POLICY_INSTALLED_KEYLESS_CUSTODY_PENDING");self.assertTrue(target.exists());self.assertTrue(r["otherAccountsUnchanged"])
            elif case=="exists":
                self.assertFalse(r["policyCreated"]);self.assertEqual(target.read_bytes(),b"unrelated")
            else:
                self.assertTrue(r["rollbackVerified"]);self.assertFalse(target.exists());self.assertEqual(r["status"],"REVIEW_REQUIRED")
            self.assertFalse(r["sshAccessEnabled"])
    def test_success(self):self.scenario("pass")
    def test_existing_file(self):self.scenario("exists")
    def test_missing_effective_restriction(self):self.scenario("mismatch")
    def test_other_account_drift(self):self.scenario("otherdrift")
    def test_reload_failure(self):self.scenario("reloadfail")

if __name__=="__main__":unittest.main()
