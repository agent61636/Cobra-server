using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace CobraHiscore
{
    /// <summary>
    /// Reads the cabinet's API key from the agent's key.dat. The agent writes it with
    /// PowerShell's ConvertFrom-SecureString: the key as UTF-16 text, encrypted with
    /// Windows DPAPI for the current user, written as hex. So only the same Windows
    /// user (arcade) can read it, and the plugin runs as that user inside LaunchBox.
    /// </summary>
    internal static class ApiKey
    {
        public static string Load(string keyPath)
        {
            var fromEnv = Environment.GetEnvironmentVariable("COBRA_HISCORE_KEY");   // testing only
            if (!string.IsNullOrEmpty(fromEnv)) return fromEnv;
            if (!File.Exists(keyPath))
                throw new FileNotFoundException("No API key yet. Run the hiscore agent's install.ps1 first.", keyPath);
            return Decrypt(File.ReadAllText(keyPath).Trim());
        }

        public static string Decrypt(string hex)
        {
            var plain = Unprotect(FromHex(hex));
            try { return Encoding.Unicode.GetString(plain); }
            finally { Array.Clear(plain, 0, plain.Length); }
        }

        internal static byte[] FromHex(string hex)
        {
            if (hex == null || hex.Length % 2 != 0) throw new FormatException("key.dat is not hex");
            var bytes = new byte[hex.Length / 2];
            for (var i = 0; i < bytes.Length; i++)
                bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            return bytes;
        }

        // Used by the tests to make a key.dat the way PowerShell does.
        internal static string EncryptForTests(string key)
        {
            var sb = new StringBuilder();
            foreach (var b in Protect(Encoding.Unicode.GetBytes(key))) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }

        [StructLayout(LayoutKind.Sequential)]
        struct DataBlob
        {
            public int Size;
            public IntPtr Data;
        }

        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CryptUnprotectData(ref DataBlob dataIn, IntPtr description, IntPtr entropy,
            IntPtr reserved, IntPtr prompt, int flags, ref DataBlob dataOut);

        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CryptProtectData(ref DataBlob dataIn, string description, IntPtr entropy,
            IntPtr reserved, IntPtr prompt, int flags, ref DataBlob dataOut);

        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr mem);

        const int UiForbidden = 0x1;

        static byte[] Unprotect(byte[] data) => Run(data, true);
        static byte[] Protect(byte[] data) => Run(data, false);

        static byte[] Run(byte[] data, bool unprotect)
        {
            var handle = GCHandle.Alloc(data, GCHandleType.Pinned);
            var input = new DataBlob { Size = data.Length, Data = handle.AddrOfPinnedObject() };
            var output = new DataBlob();
            try
            {
                var ok = unprotect
                    ? CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, UiForbidden, ref output)
                    : CryptProtectData(ref input, null, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, UiForbidden, ref output);
                if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows couldn't read key.dat (was it made by another user?)");
                var result = new byte[output.Size];
                Marshal.Copy(output.Data, result, 0, output.Size);
                return result;
            }
            finally
            {
                handle.Free();
                if (output.Data != IntPtr.Zero) LocalFree(output.Data);
            }
        }
    }
}
