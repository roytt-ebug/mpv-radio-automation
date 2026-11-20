using System;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace AutomaticMusic
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            bool fixture = args.Length > 0 && (args[0] == "--screenshot" || args[0] == "--screenshot-setup" || args[0] == "--screenshot-advanced" || args[0] == "--self-test" || args[0] == "--test-ui");
            if (fixture) return RunFixture(args);
            AppPaths paths = AppPaths.CreateDefault();
            RadioBackend backend = null;
            bool startOnSetup = args.Length == 1 && args[0] == "--setup";
            try
            {
                backend = new RadioBackend(paths);
                if (args.Length > 0 && !startOnSetup)
                {
                    if (args[0] == "--run-session" && args.Length == 2) { backend.RunSession(args[1]); return 0; }
                    if (args[0] == "--stop" && args.Length == 1) { backend.Stop(); return 0; }
                    if (args[0] == "--uninstall" && args.Length == 1) { backend.Stop(); backend.RemoveOwnedTasks(); return 0; }
                    throw new ArgumentException("Unknown command. Supported commands: --run-session morning|finisher, --stop, --uninstall.");
                }
                bool created;
                using (Mutex mutex = new Mutex(true, Product.WindowMutex, out created))
                {
                    if (!created)
                    {
                        MessageBox.Show("Automatic Music is already open. Select its window on the taskbar.", Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return 0;
                    }
                    try
                    {
                        AppSettings settings = backend.LoadSettings();
                        Application.Run(new MainForm(backend, paths, settings, false, startOnSetup));
                    }
                    finally { mutex.ReleaseMutex(); }
                }
                return 0;
            }
            catch (Exception exception)
            {
                TryLog(backend, paths, exception);
                if (args.Length == 0 || startOnSetup)
                {
                    MessageBox.Show("Automatic Music could not start.\r\n\r\n" + exception.GetBaseException().Message + "\r\n\r\nYour saved settings have not been reset.\r\nLog: " + paths.LogPath, Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                return 1;
            }
        }

        private static int RunFixture(string[] args)
        {
            try
            {
                bool setup = args[0] == "--screenshot-setup";
                bool advanced = args[0] == "--screenshot-advanced";
                bool screenshot = args[0] == "--screenshot" || setup || advanced;
                if (screenshot && args.Length != 2) throw new ArgumentException("Supply a screenshot PNG path.");
                if (!screenshot && args.Length != 1) throw new ArgumentException("Unexpected UI test arguments.");
                AppSettings sample = new AppSettings();
                if (screenshot && !setup)
                {
                    sample.Morning.PlaylistUrl = "https://www.youtube.com/playlist?list=PLexampleMorning";
                    sample.Morning.Enabled = true;
                    sample.Finisher.PlaylistUrl = "https://www.youtube.com/playlist?list=PLexampleEvening";
                }
                AppPaths fixturePaths = new AppPaths(AppDomain.CurrentDomain.BaseDirectory, Path.Combine(Path.GetTempPath(), "AutomaticMusic-UI-fixture-unused"));
                using (MainForm form = new MainForm(null, fixturePaths, sample, true, setup))
                {
                    if (screenshot)
                    {
                        string target = Path.GetFullPath(args[1]);
                        string parent = Path.GetDirectoryName(target);
                        if (!Directory.Exists(parent)) Directory.CreateDirectory(parent);
                        form.CaptureScreenshot(target, advanced ? "advanced" : null);
                    }
                    else form.RunUiSelfTest();
                }
                return 0;
            }
            catch (Exception exception)
            {
                // Fixture modes must never create or change the user's application data.
                Console.Error.WriteLine(exception.ToString());
                return 1;
            }
        }

        private static void TryLog(RadioBackend backend, AppPaths paths, Exception exception)
        {
            try
            {
                if (backend != null) backend.LogError(exception);
                else
                {
                    Directory.CreateDirectory(paths.DataRoot);
                    File.AppendAllText(paths.LogPath, DateTime.UtcNow.ToString("o") + " " + exception.ToString() + Environment.NewLine);
                }
            }
            catch { }
        }
    }
}
