// Diagnostic only: opens and closes local W32Time handles. Never calls StartService.
using System;
using System.Runtime.InteropServices;
namespace MarketBrain.Diagnostics {
    public sealed class ServiceRightResult {
        public string right;
        public uint mask;
        public bool allowed;
        public string stage;
        public int win32Error;
    }
    public static class TimeServiceAccess {
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
        private static extern IntPtr OpenSCManagerW(string machine, string database, uint access);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
        private static extern IntPtr OpenServiceW(IntPtr manager, string name, uint access);
        [DllImport("advapi32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseServiceHandle(IntPtr handle);

        public static ServiceRightResult[] Inspect() {
            string[] names = {"QUERY_CONFIG", "QUERY_STATUS", "READ_CONTROL", "SERVICE_START"};
            uint[] masks = {0x0001, 0x0004, 0x00020000, 0x0010};
            var results = new ServiceRightResult[names.Length];
            IntPtr manager = OpenSCManagerW(null, null, 0x0001); // Local SCM_CONNECT only.
            int managerError = manager == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
            try {
                for (int i=0; i<names.Length; i++) {
                    var r = new ServiceRightResult {right=names[i], mask=masks[i], stage="OpenSCManager", win32Error=managerError};
                    results[i] = r;
                    if (manager == IntPtr.Zero) continue;
                    IntPtr service = OpenServiceW(manager, "W32Time", masks[i]);
                    r.win32Error = service == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
                    r.stage = "OpenService";
                    r.allowed = service != IntPtr.Zero;
                    if (service != IntPtr.Zero) CloseServiceHandle(service);
                }
            } finally { if (manager != IntPtr.Zero) CloseServiceHandle(manager); }
            return results;
        }
    }
}
