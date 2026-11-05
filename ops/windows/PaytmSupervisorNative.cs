using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

// Windows PowerShell 5.1 compatible. No network, credentials or installation APIs.
namespace MarketBrain.Supervisor {
    public static class Lifetime {
        static IntPtr job;
        [StructLayout(LayoutKind.Sequential)] struct Basic {
            public long ProcessTime, JobTime; public uint Flags; public UIntPtr Min, Max;
            public uint Active; public UIntPtr Affinity; public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] struct Io {
            public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
        }
        [StructLayout(LayoutKind.Sequential)] struct Extended {
            public Basic Basic; public Io Io; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref Extended data, uint size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        public static void AttachCurrentProcess() {
            if (job != IntPtr.Zero) throw new InvalidOperationException("HOST_JOB_ALREADY_ATTACHED");
            IntPtr candidate = CreateJobObject(IntPtr.Zero, null);
            if (candidate == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            var limits = new Extended(); limits.Basic.Flags = 0x2000; // KILL_ON_JOB_CLOSE; no breakaway
            if (!SetInformationJobObject(candidate, 9, ref limits, (uint)Marshal.SizeOf(typeof(Extended)))) {
                int error = Marshal.GetLastWin32Error(); CloseHandle(candidate); throw new Win32Exception(error);
            }
            using (var self = Process.GetCurrentProcess()) {
                if (!AssignProcessToJobObject(candidate, self.Handle)) {
                    int error = Marshal.GetLastWin32Error(); CloseHandle(candidate); throw new Win32Exception(error);
                }
            }
            // Intentionally retained until OS process exit. Closing it here would kill self.
            // Handle is not inheritable: children cannot keep the job alive after the owner dies.
            job = candidate;
        }
    }
    public sealed class BoundedResult {
        public int ExitCode; public bool TimedOut; public string Output, Error;
    }
    public static class NativeCommand {
        static string Quote(string text) {
            if (text.IndexOfAny(new char[]{'\r','\n','\0'}) >= 0) throw new ArgumentException("HOST_ARGUMENT_INVALID");
            var b = new StringBuilder("\""); int slashes = 0;
            foreach (char c in text) {
                if (c == '\\') { slashes++; continue; }
                if (c == '"') { b.Append('\\', 2*slashes+1); b.Append(c); }
                else { b.Append('\\',slashes); b.Append(c); }
                slashes=0;
            }
            b.Append('\\',2*slashes); b.Append('"'); return b.ToString();
        }
        static async Task<string> Drain(StreamReader stream) {
            var tail = new StringBuilder(); var buffer = new char[2048]; int count;
            while ((count = await stream.ReadAsync(buffer,0,buffer.Length).ConfigureAwait(false)) != 0) {
                tail.Append(buffer,0,count);
                if (tail.Length > 16384) tail.Remove(0,tail.Length-16384);
            }
            return tail.ToString();
        }
        // Small internal seam lets tests force exit/kill races without timing guesses.
        internal interface ICommandProcess {
            bool Start(); void CloseInput(); Task<string> Output(); Task<string> Error();
            bool Wait(int milliseconds); void Kill(); bool HasExited { get; } int ExitCode { get; }
        }
        sealed class CommandProcess : ICommandProcess {
            readonly Process process;
            internal CommandProcess(Process value) { process=value; }
            public bool Start() { return process.Start(); }
            public void CloseInput() { process.StandardInput.Close(); }
            public Task<string> Output() { return Drain(process.StandardOutput); }
            public Task<string> Error() { return Drain(process.StandardError); }
            public bool Wait(int milliseconds) { return process.WaitForExit(milliseconds); }
            public void Kill() { process.Kill(); }
            public bool HasExited { get { return process.HasExited; } }
            public int ExitCode { get { return process.ExitCode; } }
        }
        static void Tag(Exception error, string operation) {
            error.GetBaseException().Data["MarketBrainOperation"]=operation;
        }
        internal static void StopOwned(ICommandProcess process) {
            try { process.Kill(); }
            catch (Exception error) {
                // Framework Kill can fail when the owned process has just exited.
                // A real denied kill of a live process must still fail closed.
                if (!(error is Win32Exception) && !(error is InvalidOperationException)) throw;
                bool exited=false;
                try { exited=process.Wait(3000); } catch { }
                if (!exited) throw;
                return;
            }
            if (!process.Wait(3000)) throw new IOException("HOST_CHILD_STOP_FAILED");
        }
        internal static BoundedResult RunCore(ICommandProcess process, int milliseconds) {
            bool started=false; Exception primary=null; string operation="START";
            try {
                started=process.Start(); if (!started) throw new InvalidOperationException("HOST_CHILD_START_FAILED");
                operation="CLOSE_INPUT"; process.CloseInput();
                operation="READ_OUTPUT"; Task<string> output=process.Output(), error=process.Error();
                operation="WAIT"; bool timeout=!process.Wait(milliseconds);
                if (timeout) { operation="TIMEOUT_STOP"; StopOwned(process); }
                operation="DRAIN";
                if (!Task.WaitAll(new Task[]{output,error},3000)) throw new IOException("HOST_CHILD_OUTPUT_TIMEOUT");
                operation="EXIT_CODE";
                return new BoundedResult { ExitCode=process.ExitCode, TimedOut=timeout, Output=output.Result, Error=error.Result };
            } catch (Exception error) { primary=error; Tag(error,operation); throw; }
            finally {
                if (started) {
                    string cleanup="CLEANUP_CHECK";
                    try { if (!process.HasExited) { cleanup="CLEANUP_STOP"; StopOwned(process); } }
                    catch (Exception error) {
                        if (primary==null) { Tag(error,cleanup); throw; }
                        // Retain the first failure; expose only structured cleanup metadata.
                        var first=primary.GetBaseException(); var last=error.GetBaseException();
                        first.Data["MarketBrainCleanupOperation"]=cleanup;
                        first.Data["MarketBrainCleanupType"]=last.GetType().Name;
                        var win32=last as Win32Exception;
                        if(win32!=null) first.Data["MarketBrainCleanupCode"]=win32.NativeErrorCode;
                    }
                }
            }
        }
        public static BoundedResult Run(string executable, string[] arguments, int milliseconds) {
            if (milliseconds < 1 || milliseconds > 30000) throw new ArgumentException("HOST_TIMEOUT_INVALID");
            var psi = new ProcessStartInfo(executable);
            psi.UseShellExecute=false; psi.CreateNoWindow=true;
            psi.RedirectStandardInput=true; psi.RedirectStandardOutput=true; psi.RedirectStandardError=true;
            var a = new StringBuilder(); foreach (string arg in arguments) { a.Append(Quote(arg)); a.Append(' '); }
            psi.Arguments=a.ToString();
            using (var process = new Process()) {
                process.StartInfo=psi;
                return RunCore(new CommandProcess(process),milliseconds);
            }
        }
    }
}
