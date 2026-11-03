using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace MarketBrain.Transport {
    // The installed host already owns a kill-on-close Windows job; children inherit it.
    public sealed class Child : IDisposable {
        readonly Process process;
        readonly StringBuilder errors = new StringBuilder();
        readonly object sync = new object();
        readonly Task stdout, stderr;
        bool disposed;
        public int Id { get { return process.Id; } }
        public long StartTicks { get { return process.StartTime.ToUniversalTime().Ticks; } }
        public bool Exited { get { return process.HasExited; } }
        public string ErrorTail { get { lock(sync) { return errors.ToString(); } } }
        static string Quote(string value) {
            if(value.IndexOfAny(new char[]{'\r','\n','\0'}) >= 0) throw new ArgumentException("TRANSPORT_ARGUMENT_INVALID");
            var b=new StringBuilder("\""); int n=0;
            foreach(char c in value) {
                if(c=='\\') { n++; continue; }
                if(c=='"') { b.Append('\\',2*n+1); b.Append(c); }
                else { b.Append('\\',n); b.Append(c); }
                n=0;
            }
            return b.Append('\\',2*n).Append('"').ToString();
        }
        async Task Drain(StreamReader reader, bool retain) {
            var buffer=new char[2048]; int n;
            while((n=await reader.ReadAsync(buffer,0,buffer.Length).ConfigureAwait(false))!=0) {
                if(retain) lock(sync) { errors.Append(buffer,0,n); if(errors.Length>16384) errors.Remove(0,errors.Length-16384); }
            }
        }
        public Child(string executable, string[] arguments) {
            var info=new ProcessStartInfo(executable);
            info.UseShellExecute=false; info.CreateNoWindow=true;
            info.RedirectStandardInput=true; info.RedirectStandardOutput=true; info.RedirectStandardError=true;
            var args=new StringBuilder(); foreach(var arg in arguments) args.Append(Quote(arg)).Append(' ');
            info.Arguments=args.ToString(); process=new Process(); process.StartInfo=info;
            bool started=false;
            try {
                if(!process.Start()) throw new IOException("TRANSPORT_CHILD_START_FAILED");
                started=true;
                process.StandardInput.Close(); stdout=Drain(process.StandardOutput,false); stderr=Drain(process.StandardError,true);
            } catch { try { if(started && !process.HasExited) { process.Kill(); process.WaitForExit(3000); } } finally { process.Dispose(); } throw; }
        }
        public void Dispose() {
            if(disposed) return;
            try {
                if(!process.HasExited) process.Kill();
                if(!process.WaitForExit(3000)) throw new IOException("TRANSPORT_CHILD_STOP_FAILED");
                if(!Task.WaitAll(new Task[]{stdout,stderr},3000)) throw new IOException("TRANSPORT_OUTPUT_STOP_FAILED");
            } finally { disposed=true; process.Dispose(); }
        }
    }
    public sealed class Listener {
        public string Address; public int Port, ProcessId;
    }
    public static class Network {
        [DllImport("iphlpapi.dll",SetLastError=true)] static extern uint GetExtendedTcpTable(IntPtr table,ref int size,bool order,int family,int kind,uint reserved);
        public static Listener[] Listeners(int port) {
            if(port<1 || port>65535) throw new ArgumentException("TRANSPORT_PORT_INVALID");
            var rows=new List<Listener>();
            foreach(int family in new int[]{2,23}) {
                int size=0; uint code=GetExtendedTcpTable(IntPtr.Zero,ref size,false,family,3,0);
                if(code!=122 || size<4 || size>16777216) throw new Win32Exception((int)code);
                IntPtr buffer=IntPtr.Zero;
                try {
                    // Connections can change between sizing and retrieval. Retry only resizing,
                    // with an allocation cap; never accept an incomplete ownership snapshot.
                    for(int attempt=0;attempt<3;attempt++) {
                        if(size<4 || size>16777216) throw new IOException("TRANSPORT_TABLE_INVALID");
                        if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer);
                        buffer=IntPtr.Zero; buffer=Marshal.AllocHGlobal(size);
                        code=GetExtendedTcpTable(buffer,ref size,false,family,3,0);
                        if(code!=122) break;
                    }
                    if(code!=0) throw new Win32Exception((int)code);
                    int count=Marshal.ReadInt32(buffer), stride=family==2?24:56;
                    if(count<0 || count>(size-4)/stride) throw new IOException("TRANSPORT_TABLE_INVALID");
                    for(int i=0;i<count;i++) {
                        IntPtr p=IntPtr.Add(buffer,4+i*stride); int offset=family==2?8:20;
                        int localPort=(Marshal.ReadByte(p,offset)<<8)|Marshal.ReadByte(p,offset+1);
                        if(localPort!=port) continue;
                        byte[] address=new byte[family==2?4:16]; Marshal.Copy(IntPtr.Add(p,family==2?4:0),address,0,address.Length);
                        rows.Add(new Listener { Address=new IPAddress(address).ToString(),Port=localPort,ProcessId=Marshal.ReadInt32(p,family==2?20:52) });
                    }
                } finally { if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer); }
            }
            return rows.ToArray();
        }
    }
}
