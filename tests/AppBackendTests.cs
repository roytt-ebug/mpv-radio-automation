using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Principal;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Xml;
using AutomaticMusic;

// Compile as AppBackendTests.exe, referencing the built AutomaticMusic.exe.
// No arguments: deterministic core checks. <appdir>: core + unique disabled
// Task Scheduler roundtrip. --scheduler-only <appdir>: the roundtrip alone.
internal static class AppBackendTests
{
    private static int checks;
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);

    private static int Main(string[] args)
    {
        try
        {
            bool schedulerOnly = args.Length > 0 && args[0] == "--scheduler-only";
            if (schedulerOnly && args.Length != 2) throw new ArgumentException("Supply --scheduler-only <appdir>.");
            if (!schedulerOnly) RunCore();
            if (args.Length > 0)
            {
                string appDirectory = schedulerOnly ? args[1] : args[0];
                RunScheduler(Path.Combine(Path.GetFullPath(appDirectory), "AutomaticMusic.exe"));
            }
            Console.WriteLine("PASS: " + checks + " desktop backend checks; safe URLs, settings, configuration, task ownership and rollback" + (args.Length > 0 ? "; real disabled user task roundtrip." : "."));
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error.ToString()); return 1; }
    }

    private static void Check(bool condition, string label)
    {
        checks++;
        if (!condition) throw new Exception("FAILED: " + label);
    }

    private static void Reject(Action action, string label)
    {
        bool rejected = false;
        try { action(); } catch { rejected = true; }
        Check(rejected, label);
    }

    private static void RunCore()
    {
        Check(RadioBackend.NormalizePlaylistUrl(" https://music.youtube.com/watch?v=test&list=PL_test-123&si=x ") == "https://www.youtube.com/playlist?list=PL_test-123", "canonical playlist strips unrelated tracking/video fields");
        Check(RadioBackend.NormalizePlaylistUrl("http://youtu.be/test?list=PLvalid") == "https://www.youtube.com/playlist?list=PLvalid", "valid shared playlist normalizes to HTTPS");
        foreach (string bad in new string[] {
            "", "file:///C:/private.txt", "javascript:alert(1)", "https://youtube.com.evil.test/playlist?list=PLtest",
            "https://user@youtube.com/playlist?list=PLtest", "https://youtube.com:1234/playlist?list=PLtest",
            "https://youtube.com/watch?v=test", "https://youtube.com/playlist#list=PLtest",
            "https://youtube.com/playlist?list=PLone&list=PLtwo", "https://youtube.com/playlist?list=PL%22bad",
            "https://youtube.com/playlist?list=PLgood\nhttps://youtube.com/playlist?list=PLother" })
        {
            string candidate = bad;
            Reject(delegate { RadioBackend.NormalizePlaylistUrl(candidate); }, "reject unsafe/non-playlist URL: " + candidate.Replace("\n", " newline "));
        }
        var settings = new AppSettings();
        RadioBackend.ValidateSettings(settings);
        Check(!settings.Morning.Enabled && !settings.Finisher.Enabled, "fresh schedules are disabled");
        settings.Morning.Days = new string[0];
        RadioBackend.ValidateSettings(settings);
        Check(true, "disabled schedule may have no selected days");
        settings.Morning.Enabled = true;
        settings.Morning.PlaylistUrl = "https://www.youtube.com/playlist?list=PLtest";
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "enabled schedule requires a day");
        settings.Morning.Days = new string[] { "Mon", "Mon" };
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "duplicate days rejected");
        settings.Morning.Days = new string[] { "Mon" };
        settings.Morning.StartTime = "24:00";
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "invalid stored clock rejected");
        settings.Morning.StartTime = "06:45";
        settings.Morning.PlaylistUrl = "";
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "enabled schedule requires playlist");
        settings.Morning.Enabled = false;
        settings.SampleMinMinutes = 31;
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "sample min/max order validated");
        settings.SampleMinMinutes = 10;
        settings.FadeSeconds = Double.NaN;
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "NaN setting rejected");
        settings.FadeSeconds = 5;
        settings.AudioDeviceId = "auto\nvolume=0";
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "device cannot inject config line");
        settings.AudioDeviceId = "auto";
        settings.Morning.DurationMinutes = 1441;
        Reject(delegate { RadioBackend.ValidateSettings(settings); }, "session duration bounded");

        Check(RadioBackend.QuoteArgument("C:\\folder\\") == "\"C:\\folder\\\\\"", "Windows trailing slash quoting");
        Check(RadioBackend.QuoteArgument("a\"b") == "\"a\\\"b\"", "Windows embedded quote quoting");
        Check(RadioBackend.QuoteArgument("") == "\"\"", "empty Windows argument");
        Check(RadioBackend.QuoteArgument("x & y") == "\"x & y\"", "shell metacharacters remain literal argument content");
        Check(RadioBackend.RadioKey("C:\\Music\\") == RadioBackend.RadioKey("c:\\music"), "same Windows installation has same IPC identity");
        Check(RadioBackend.RadioKey("C:\\Music") != RadioBackend.RadioKey("C:\\Other"), "independent installations have independent IPC");
        string parent = Path.Combine(Path.GetTempPath(), "Components");
        RadioBackend.RequireContainedPath(parent, Path.Combine(parent, "bundle", "mpv.exe"));
        Check(true, "component child path accepted");
        Reject(delegate { RadioBackend.RequireContainedPath(parent, parent + "-evil\\mpv.exe"); }, "prefix lookalike is not a child path");
        Reject(delegate { RadioBackend.RequireContainedPath(parent, Path.Combine(parent, "..", "mpv.exe")); }, "component traversal rejected");

        List<AudioDeviceInfo> devices = RadioBackend.ParseAudioDevices("List of detected audio devices:\r\n  'auto' (Autoselect device)\r\n  'wasapi/{test-id}' (Speakers (USB Audio))\r\n  'auto' (duplicate)\r\n");
        Check(devices.Count == 2 && devices[0].Id == "auto" && devices[1].Name == "Speakers (USB Audio)", "audio device parsing handles parentheses and removes duplicates");
        Reject(delegate { RadioBackend.ParseAudioDevices("unrelated output"); }, "missing audio list produces clear failure");

        TestConfiguration();
        TestTaskOwnership();
        TestRollback();
        TestSettingsLoad();
        TestComponentReceipt();
    }

    private static void TestConfiguration()
    {
        var settings = new AppSettings { AudioDeviceId = "wasapi/new", Volume = 31 };
        string original = "# Caf\u00e9\r\naudio-device=auto # output\r\nvolume=80\r\ncache=yes\r\n[headphones]\r\naudio-device=wasapi/keep\r\nvolume=22\r\n[]\r\n--audio-device='old#device' # second global\r\nvolume=15";
        string expected = "# Caf\u00e9\r\naudio-device=wasapi/new # output\r\nvolume=31\r\ncache=yes\r\n[headphones]\r\naudio-device=wasapi/keep\r\nvolume=22\r\n[]\r\n--audio-device=wasapi/new # second global\r\nvolume=31";
        byte[] before = new byte[] { 239, 187, 191 }.Concat(Utf8.GetBytes(original)).ToArray();
        byte[] after = RadioBackend.MergeMpvSettings(before, settings);
        Check(after.SequenceEqual(new byte[] { 239, 187, 191 }.Concat(Utf8.GetBytes(expected))), "speaker/volume update keeps BOM, CRLF, comments and named profiles; [] resumes global scope");
        Check(RadioBackend.MergeMpvSettings(after, settings).SequenceEqual(after), "repeated MPV merge is byte-idempotent");
        string onlyProfile = "[headphones]\naudio-device=keep\nvolume=22";
        string merged = Utf8.GetString(RadioBackend.MergeMpvSettings(Utf8.GetBytes(onlyProfile), settings));
        Check(merged.StartsWith("audio-device=wasapi/new\nvolume=31\n") && merged.EndsWith(onlyProfile), "missing global settings inserted before named profiles");
        settings.AudioDeviceId = "wasapi/Caf\u00e9#speaker";
        string encoded = RadioBackend.ConfigValue(settings.AudioDeviceId);
        Check(encoded == "%" + Utf8.GetByteCount(settings.AudioDeviceId) + "%" + settings.AudioDeviceId, "unusual UTF-8 device ID uses byte-count quoting");
        after = RadioBackend.MergeMpvSettings(after, settings);
        Check(Utf8.GetString(after).Contains("audio-device=" + encoded + " # output"), "inline comment remains separate from quoted device hash");
        settings.AudioDeviceId = "auto";
        Check(Utf8.GetString(RadioBackend.MergeMpvSettings(after, settings)).Contains("audio-device=auto # output"), "byte-count device quoting can be updated again");
        Reject(delegate { RadioBackend.MergeMpvSettings(new byte[] { 255, 254, 97, 0 }, settings); }, "unsupported config encoding is rejected");
        Reject(delegate { RadioBackend.MergeMpvSettings(Utf8.GetBytes("audio-device=\"unclosed"), settings); }, "unclosed existing config quote rejected");
        Reject(delegate { RadioBackend.MergeMpvSettings(Utf8.GetBytes("audio-device=%99%short"), settings); }, "truncated existing byte-count value rejected");
        settings.SamplingEnabled = false;
        settings.SampleMinMinutes = 4;
        settings.SampleMaxMinutes = 8;
        string sampling = Utf8.GetString(RadioBackend.MergeSamplingSettings(Utf8.GetBytes("# my custom preferences\nsection_mode=yes # mode\nhistory_max_age_days=365\nsection_min_minutes=10\nsection_max_minutes=30"), settings));
        Check(sampling.Contains("section_mode=no # mode") && sampling.Contains("history_max_age_days=365") && sampling.Contains("section_min_minutes=4") && sampling.Contains("section_max_minutes=8"), "managed sampling fields change while advanced custom options remain");
    }

    private static void TestTaskOwnership()
    {
        string sid = WindowsIdentity.GetCurrent().User.Value;
        string executable = Path.Combine(Path.GetTempPath(), "Automatic Music & Test", "AutomaticMusic.exe");
        var session = new SessionSettings { Enabled = true, Days = new string[] { "Mon", "Fri" }, DurationMinutes = 45 };
        string xml = RadioBackend.BuildTaskXml(session, "morning", true, sid, executable);
        RadioBackend.ValidateTaskOwnership(xml, "morning", sid, executable);
        Check(true, "generated task passes ownership validation");
        var document = new XmlDocument { XmlResolver = null }; document.LoadXml(xml);
        var ns = new XmlNamespaceManager(document.NameTable); ns.AddNamespace("t", "http://schemas.microsoft.com/windows/2004/02/mit/task");
        Check(document.SelectSingleNode("/t:Task/t:Settings/t:ExecutionTimeLimit", ns).InnerText == "PT46M", "task duration adds only one cleanup minute");
        Check(document.SelectSingleNode("/t:Task/t:Settings/t:StartWhenAvailable", ns).InnerText == "false", "missed starts do not start late");
        Check(document.SelectSingleNode("/t:Task/t:Settings/t:RestartOnFailure", ns) == null, "no automatic retry extends the session");
        Check(document.SelectSingleNode("/t:Task/t:Principals/t:Principal/t:RunLevel", ns).InnerText == "LeastPrivilege", "task does not elevate playback");
        Check(document.SelectSingleNode("/t:Task/t:Principals/t:Principal/t:LogonType", ns).InnerText == "InteractiveToken", "task uses logged-in audio session without password");
        Check(document.SelectSingleNode("/t:Task/t:Settings/t:StopIfGoingOnBatteries", ns).InnerText == "false", "battery or UPS does not unexpectedly stop music");
        Check(document.SelectNodes("/t:Task/t:Triggers/t:CalendarTrigger/t:ScheduleByWeek/t:DaysOfWeek/*", ns).Count == 2, "selected weekdays emitted exactly");
        Reject(delegate { RadioBackend.ValidateTaskOwnership(xml.Replace("--run-session morning", "--run-session finisher"), "morning", sid, executable); }, "foreign action rejected even with copied description");
        Reject(delegate { RadioBackend.ValidateTaskOwnership(xml.Replace("managed session", "unrelated task"), "morning", sid, executable); }, "foreign description rejected");
        Reject(delegate { RadioBackend.ValidateTaskOwnership(xml, "morning", sid, executable + ".other"); }, "foreign executable rejected");
        Reject(delegate { RadioBackend.ValidateTaskOwnership("<!DOCTYPE task [<!ENTITY x SYSTEM 'file:///C:/secret'>]><task>&x;</task>", "morning", sid, executable); }, "task XML external entities rejected");
    }

    private static void TestRollback()
    {
        string work = Path.Combine(Path.GetTempPath(), "AutomaticMusic-backend-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            string config = Path.Combine(work, "mpv.conf");
            string json = Path.Combine(work, "settings.json");
            File.WriteAllText(config, "old config", Utf8); File.WriteAllText(json, "old json", Utf8);
            var files = new List<FileUpdate> { new FileUpdate(config, Utf8.GetBytes("new config")), new FileUpdate(json, Utf8.GetBytes("new json")) };
            var tasks = new Dictionary<string, string> { { "morning", "new morning" }, { "finisher", "new finisher" } };
            var failedStore = new FakeScheduleStore(); failedStore.FailNextFinisherWrite = true;
            Reject(delegate { RadioBackend.CommitSettings(failedStore, files, tasks); }, "failed second task aborts settings transaction");
            Check(File.ReadAllText(config) == "old config" && File.ReadAllText(json) == "old json", "file contents roll back after task failure");
            Check(failedStore.Tasks["morning"] == "old morning" && failedStore.Tasks["finisher"] == "old finisher", "both tasks roll back after partial update");
            Check(Directory.GetFiles(work, "*.new-*").Length == 0, "no staging files left after rollback");
            var store = new FakeScheduleStore(); RadioBackend.CommitSettings(store, files, tasks);
            Check(File.ReadAllText(config) == "new config" && File.ReadAllText(json) == "new json" && store.Tasks["morning"] == "new morning", "successful transaction commits settings and tasks");
            File.WriteAllText(config, "keep me", Utf8);
            store = new FakeScheduleStore(); store.ForeignTask = true;
            Reject(delegate { RadioBackend.CommitSettings(store, files, tasks); }, "ownership conflict blocks save before any write");
            Check(File.ReadAllText(config) == "keep me", "ownership conflict preserves configuration");
            string notCreated = Path.Combine(work, "new-file.json");
            files = new List<FileUpdate> { new FileUpdate(notCreated, Utf8.GetBytes("new")), new FileUpdate(json, Utf8.GetBytes("later")) };
            store = new FakeScheduleStore(); store.FailNextFinisherWrite = true;
            Reject(delegate { RadioBackend.CommitSettings(store, files, tasks); }, "failure also rolls back newly created files");
            Check(!File.Exists(notCreated), "rollback removes only transaction-created new file");
        }
        finally { Directory.Delete(work, true); }
    }

    private static void TestSettingsLoad()
    {
        string work = Path.Combine(Path.GetTempPath(), "AutomaticMusic-settings-" + Guid.NewGuid().ToString("N"));
        try
        {
            var backend = new RadioBackend(new AppPaths(Path.GetTempPath(), work));
            AppSettings settings = backend.LoadSettings();
            Check(!settings.Morning.Enabled && !Directory.Exists(work), "reading defaults creates no files or schedules");
            Directory.CreateDirectory(work);
            string path = Path.Combine(work, "settings.json");
            string invalid = "{\"Schema\":1,\"Morning\":{\"StartTime\":\"90:00\"}}";
            File.WriteAllText(path, invalid, Utf8);
            Reject(delegate { backend.LoadSettings(); }, "invalid stored settings rejected before UI can normalize them");
            Check(File.ReadAllText(path) == invalid, "malformed settings are never silently reset");
        }
        finally { if (Directory.Exists(work)) Directory.Delete(work, true); }
    }

    private static void TestComponentReceipt()
    {
        string work = Path.Combine(Path.GetTempPath(), "AutomaticMusic-components-" + Guid.NewGuid().ToString("N"));
        string install = Path.Combine(work, "App"), data = Path.Combine(work, "Data");
        string bundle = Path.Combine(data, "Components", "fixture");
        Directory.CreateDirectory(install); Directory.CreateDirectory(bundle);
        var json = new JavaScriptSerializer();
        try
        {
            string manifest = Path.Combine(install, "components.lock.json");
            File.WriteAllText(manifest, "{\"schema\":1,\"bundle\":\"fixture\"}", Utf8);
            string hash;
            using (SHA256 sha = SHA256.Create()) hash = BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(manifest))).Replace("-", "").ToLowerInvariant();
            var versions = new Dictionary<string, object> { { "mpv", "test-mpv" }, { "ytDlp", "test-ytdlp" }, { "deno", "test-deno" } };
            var files = new List<Dictionary<string, object>>();
            foreach (string name in new string[] { "mpv.exe", "mpv.com", "yt-dlp.exe", "deno.exe" })
            {
                File.WriteAllBytes(Path.Combine(bundle, name), new byte[] { 1, 2, 3 });
                files.Add(new Dictionary<string, object> { { "path", name }, { "length", 3 }, { "sha256", new string('0', 64) } });
            }
            var pointer = new Dictionary<string, object> { { "schema", 1 }, { "bundle", "fixture" }, { "directory", bundle }, { "versions", versions } };
            var marker = new Dictionary<string, object> { { "schema", 1 }, { "bundle", "fixture" }, { "manifestSha256", hash }, { "versions", versions }, { "files", files } };
            string pointerPath = Path.Combine(data, "components.json"), markerPath = Path.Combine(bundle, "bundle.json");
            File.WriteAllText(pointerPath, json.Serialize(pointer), Utf8); File.WriteAllText(markerPath, json.Serialize(marker), Utf8);
            var backend = new RadioBackend(new AppPaths(install, data));
            ComponentStatus status = backend.GetComponentStatus();
            Check(status.Ready && status.Directory == bundle && status.DenoVersion == "test-deno", "component DTO receipt resolves without executing fixture files");
            string failure = "";
            try { backend.GetAudioDevices(); } catch (Exception error) { failure = error.Message; }
            Check(failure.Contains("has changed"), "execution verifies component hashes before launching any fixture file");
            pointer["directory"] = install;
            File.WriteAllText(pointerPath, json.Serialize(pointer), Utf8);
            Check(!backend.GetComponentStatus().Ready, "component pointer cannot select an executable outside its owned folder");
            pointer["directory"] = bundle; File.WriteAllText(pointerPath, json.Serialize(pointer), Utf8);
            marker["bundle"] = "foreign"; File.WriteAllText(markerPath, json.Serialize(marker), Utf8);
            Check(!backend.GetComponentStatus().Ready, "component marker must match the selected bundle");
            marker["bundle"] = "fixture"; marker["manifestSha256"] = new string('0', 64); File.WriteAllText(markerPath, json.Serialize(marker), Utf8);
            Check(!backend.GetComponentStatus().Ready, "component marker must match the installed app manifest");
            marker["manifestSha256"] = hash;
            marker["versions"] = new Dictionary<string, object> { { "mpv", "different" }, { "ytDlp", "test-ytdlp" }, { "deno", "test-deno" } };
            File.WriteAllText(markerPath, json.Serialize(marker), Utf8);
            Check(!backend.GetComponentStatus().Ready, "receipt versions must agree with bundle ownership marker");
        }
        finally { Directory.Delete(work, true); }
    }

    private static void RunScheduler(string executable)
    {
        if (!File.Exists(executable)) throw new FileNotFoundException("Supply the built or installed app directory.", executable);
        string sid = WindowsIdentity.GetCurrent().User.Value;
        using (var store = new WindowsScheduleStore(sid, executable, Guid.NewGuid().ToString("N")))
        {
            try
            {
                Check(store.Snapshot().Values.All(delegate(string value) { return value == null; }), "unique scheduler fixture begins empty");
                var session = new SessionSettings { Enabled = true, Days = new string[] { "Mon", "Wed" }, DurationMinutes = 30 };
                // Disable both the trigger and task before registering. No actual
                // playlist or music process can start, even if the clock matches.
                string morning = RadioBackend.BuildTaskXml(session, "morning", false, sid, executable).Replace("<Enabled>true</Enabled>", "<Enabled>false</Enabled>");
                string finisher = RadioBackend.BuildTaskXml(session, "finisher", false, sid, executable).Replace("<Enabled>true</Enabled>", "<Enabled>false</Enabled>");
                store.Set("morning", morning); store.Set("finisher", finisher);
                Dictionary<string, string> saved = store.Snapshot();
                Check(saved["morning"] != null && saved["finisher"] != null, "standard user can register and read disabled owned tasks");
                Check(saved["morning"].Contains("<Enabled>false</Enabled>"), "roundtripped fixture remains disabled");
                RadioBackend.ValidateTaskOwnership(saved["morning"], "morning", sid, executable);
                Check(true, "Windows-normalized task retains verified ownership");
                Reject(delegate { store.Set("morning", morning.Replace("--run-session morning", "--uninstall")); }, "live store refuses unowned action replacement");
                store.Set("morning", null);
                Check(store.Snapshot()["morning"] == null && store.Snapshot()["finisher"] != null, "removal touches only the selected owned task");
                store.Set("finisher", null);
                Check(store.Snapshot().Values.All(delegate(string value) { return value == null; }), "owned task removal is complete");
            }
            finally
            {
                store.Set("morning", null); store.Set("finisher", null); store.RemoveEmptyTestFolder();
            }
        }
    }

    private sealed class FakeScheduleStore : IScheduleStore
    {
        public readonly Dictionary<string, string> Tasks = new Dictionary<string, string> { { "morning", "old morning" }, { "finisher", "old finisher" } };
        public bool FailNextFinisherWrite;
        public bool ForeignTask;
        public Dictionary<string, string> Snapshot()
        {
            if (ForeignTask) throw new InvalidOperationException("Unrelated task must not be changed.");
            return new Dictionary<string, string>(Tasks);
        }
        public void Set(string key, string xml)
        {
            if (key == "finisher" && FailNextFinisherWrite) { FailNextFinisherWrite = false; throw new IOException("Injected registration failure."); }
            Tasks[key] = xml;
        }
        public void Dispose() { }
    }
}
