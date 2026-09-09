// Launch-only Windows helper. Radio.ps1 remains the session supervisor.
// Built as a Windows application (no console), with no third-party libraries.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class RadioHidden
{
    private const int DiagnosticLimit = 32768;

    // Quote one Windows native argument, including embedded quotes/trailing slashes.
    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    private static void SaveError(string folder, string message)
    {
        // One bounded, local error file; never touch playback/history files.
        try
        {
            if (message.Length > DiagnosticLimit) message = message.Substring(0, DiagnosticLimit);
            File.WriteAllText(Path.Combine(folder, "Radio-Hidden-error.log"),
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + Environment.NewLine + message,
                new UTF8Encoding(false));
        }
        catch { /* Task Scheduler still receives the nonzero exit code. */ }
    }

    private static int Main(string[] args)
    {
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        try
        {
            string script = Path.Combine(folder, "Radio.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("Missing adjacent Radio.ps1.", script);
            var arguments = new StringBuilder(
                "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ");
            arguments.Append(Quote(script));
            foreach (string arg in args) arguments.Append(' ').Append(Quote(arg));

            var start = new ProcessStartInfo
            {
                // Never resolve powershell.exe through PATH or use a command shell.
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe"),
                WorkingDirectory = folder,
                Arguments = arguments.ToString(),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            var diagnostics = new StringBuilder();
            DataReceivedEventHandler capture = delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data == null) return;
                lock (diagnostics)
                {
                    int remaining = DiagnosticLimit - diagnostics.Length;
                    if (remaining > 0)
                    {
                        string line = e.Data + Environment.NewLine;
                        diagnostics.Append(line, 0, Math.Min(remaining, line.Length));
                    }
                }
            };
            using (var child = new Process { StartInfo = start })
            {
                child.OutputDataReceived += capture;
                child.ErrorDataReceived += capture;
                child.Start();
                child.StandardInput.Close();
                child.BeginOutputReadLine();
                child.BeginErrorReadLine();
                child.WaitForExit();
                int code = child.ExitCode;
                if (code != 0)
                    SaveError(folder, "PowerShell exit code: " + code + Environment.NewLine + diagnostics);
                return code;
            }
        }
        catch (Exception error)
        {
            SaveError(folder, error.ToString());
            return 1;
        }
    }
}
