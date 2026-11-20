using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Xml;

[assembly: InternalsVisibleTo("AppBackendTests")]

namespace AutomaticMusic
{
    // All paths and tasks belong to this Windows user. Blocking operations are
    // intentionally synchronous; the form runs them on its background worker.
    public sealed class RadioBackend
    {
        private readonly AppPaths paths;
        private readonly string userSid;
        private readonly string endpoint;
        private readonly string operationMutex;
        private readonly List<PlaybackWorker> workers = new List<PlaybackWorker>();
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        private static readonly string[] SessionKeys = { "morning", "finisher" };
        private static readonly string[] DayKeys = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
        private static readonly string[] DayNames = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
        private static readonly string[] RequiredComponents = { "mpv.exe", "mpv.com", "yt-dlp.exe", "deno.exe" };

        public RadioBackend(AppPaths appPaths)
        {
            if (appPaths == null) throw new ArgumentNullException("appPaths");
            paths = appPaths;
            userSid = WindowsIdentity.GetCurrent().User.Value;
            endpoint = "mpv-radio-" + RadioKey(paths.PlayerRoot);
            operationMutex = "AutomaticMusic.Settings." + RadioKey(paths.DataRoot);
        }

        public AppSettings LoadSettings()
        {
            if (!File.Exists(paths.SettingsPath)) return new AppSettings();
            try
            {
                AppSettings settings = Serializer().Deserialize<AppSettings>(ReadText(paths.SettingsPath, 1024 * 1024));
                ValidateSettings(settings);
                return settings;
            }
            catch (Exception error)
            {
                throw new InvalidOperationException("Your saved settings could not be read. They have been kept at " + paths.SettingsPath + ". " + error.Message, error);
            }
        }

        public void SaveSettings(AppSettings settings)
        {
            AppSettings copy = CloneSettings(settings);
            ValidateSettings(copy);
            if (copy.Morning.Enabled || copy.Finisher.Enabled) RequireComponents(false);
            WithOperationLock(delegate
            {
                string configDirectory = Path.Combine(paths.PlayerRoot, "portable_config");
                string mpvConfig = Path.Combine(configDirectory, "mpv.conf");
                string options = Path.Combine(configDirectory, "script-opts", "random-start.conf");
                var updates = new List<FileUpdate>();
                updates.Add(new FileUpdate(mpvConfig, MergeMpvSettings(File.Exists(mpvConfig) ? File.ReadAllBytes(mpvConfig) : null, copy)));
                updates.Add(new FileUpdate(options, MergeSamplingSettings(File.Exists(options) ? File.ReadAllBytes(options) : null, copy)));
                // Commit the human-facing settings last, after both task definitions.
                updates.Add(new FileUpdate(paths.SettingsPath, Utf8.GetBytes(Serializer().Serialize(copy))));
                var definitions = new Dictionary<string, string>();
                foreach (string key in SessionKeys)
                    definitions[key] = copy.GetSession(key).Enabled ? BuildTaskXml(copy.GetSession(key), key, copy.WakeComputer, userSid, paths.ExecutablePath) : null;
                using (IScheduleStore store = new WindowsScheduleStore(userSid, paths.ExecutablePath))
                    CommitSettings(store, updates, definitions);
            });
        }

        public ComponentStatus GetComponentStatus()
        {
            try
            {
                ComponentPointer bundle = RequireComponents(false);
                return new ComponentStatus { Ready = true, Message = "All playback components are installed.", Bundle = bundle.bundle,
                    Directory = bundle.directory, MpvVersion = bundle.versions.mpv, YtDlpVersion = bundle.versions.ytDlp, DenoVersion = bundle.versions.deno };
            }
            catch (Exception error) { return new ComponentStatus { Ready = false, Message = error.Message }; }
        }

        public void InstallComponents(bool repair, Action<string> progress)
        {
            string installer = Path.Combine(paths.InstallRoot, "Install-Components.ps1");
            string manifest = Path.Combine(paths.InstallRoot, "components.lock.json");
            if (!File.Exists(installer) || !File.Exists(manifest))
                throw new InvalidOperationException("The component installer is missing. Reinstall Automatic Music.");
            var args = PowerShellArguments(installer);
            args.AddRange(new string[] { "-DataRoot", paths.DataRoot, "-ManifestPath", manifest });
            if (repair) args.Add("-Repair");
            RunTool(PowerShellPath(), args, paths.InstallRoot, null, 20 * 60 * 1000, progress);
            RequireComponents(false);
        }

        public List<AudioDeviceInfo> GetAudioDevices()
        {
            ComponentPointer bundle = RequireComponents(true);
            string output = RunTool(Path.Combine(bundle.directory, "mpv.com"),
                new string[] { "--no-config", "--load-scripts=no", "--audio-device=help" }, bundle.directory, bundle.directory, 15000, null);
            return ParseAudioDevices(output);
        }

        internal static List<AudioDeviceInfo> ParseAudioDevices(string output)
        {
            var devices = new List<AudioDeviceInfo>();
            foreach (string line in output.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                Match match = Regex.Match(line, @"^\s*'(?<id>[^'\r\n]+)'\s*\((?<name>.*)\)\s*$");
                if (!match.Success) continue;
                string id = match.Groups["id"].Value;
                if (devices.Any(delegate(AudioDeviceInfo device) { return device.Id == id; })) continue;
                devices.Add(new AudioDeviceInfo { Id = id, Name = id == "auto" ? "Windows default output" : match.Groups["name"].Value });
            }
            if (devices.Count == 0) throw new InvalidOperationException("MPV could not find an audio output. Connect your speaker and try Refresh.");
            return devices;
        }

        public PlaylistVerification VerifyPlaylist(string playlistUrl)
        {
            string url = NormalizePlaylistUrl(playlistUrl);
            ComponentPointer bundle = RequireComponents(true);
            string output = RunTool(Path.Combine(bundle.directory, "yt-dlp.exe"),
                new string[] { "--ignore-config", "--flat-playlist", "--playlist-end", "1", "--skip-download", "--dump-single-json",
                    "--no-warnings", "--socket-timeout", "12", "--retries", "1", "--extractor-retries", "1",
                    "--js-runtimes", "deno:" + Path.Combine(bundle.directory, "deno.exe"), "--", url },
                bundle.directory, bundle.directory, 45000, null);
            Dictionary<string, object> result;
            try { result = Serializer().Deserialize<Dictionary<string, object>>(output.Trim()); }
            catch (Exception error) { throw new InvalidOperationException("YouTube returned an unexpected playlist response. Try Repair components, then check the link again.", error); }
            object entries;
            if (!result.TryGetValue("entries", out entries) || !(entries is System.Collections.IList) || ((System.Collections.IList)entries).Count == 0)
                throw new InvalidOperationException("This playlist has no accessible entries. Use a public or unlisted playlist with playable videos.");
            object title;
            return new PlaylistVerification { Url = url, Title = result.TryGetValue("title", out title) ? Convert.ToString(title, CultureInfo.InvariantCulture) : "YouTube playlist",
                Message = "Playlist found. Press Play to confirm that its audio works on this computer." };
        }

        public void Play(AppSettings settings, string sessionKey)
        {
            AppSettings copy = CloneSettings(settings);
            ValidateSettings(copy);
            SessionSettings session = copy.GetSession(sessionKey);
            string url = NormalizePlaylistUrl(session.PlaylistUrl);
            ComponentPointer bundle = RequireComponents(true);
            WithOperationLock(delegate
            {
                CleanupWorkers();
                PreparePlaybackConfig(copy);
                StartPlayback(bundle, url, session.DurationMinutes * 60, false, copy.AudioDeviceId, copy.Volume, true);
            });
        }

        // Task Scheduler keeps this small GUI-subsystem process alive until its
        // own supervisor exits. It never launches a form or extends the duration.
        public void RunSession(string sessionKey)
        {
            PlaybackWorker worker = null;
            WithOperationLock(delegate
            {
                // Save commits task definitions before its final settings JSON.
                // A task firing during that transaction must wait before reading.
                AppSettings settings = LoadSettings();
                SessionSettings session = settings.GetSession(sessionKey);
                if (!session.Enabled) return;
                ComponentPointer bundle = RequireComponents(true);
                PreparePlaybackConfig(settings);
                worker = StartPlayback(bundle, NormalizePlaylistUrl(session.PlaylistUrl), session.DurationMinutes * 60,
                    false, settings.AudioDeviceId, settings.Volume, true);
            });
            if (worker == null) return;
            try
            {
                worker.Process.WaitForExit();
                if (worker.Process.ExitCode != 0) throw new InvalidOperationException("Scheduled playback stopped with an error. " + worker.Output.Text);
            }
            finally { worker.Process.Dispose(); workers.Remove(worker); }
        }

        public void TestSpeaker(string deviceId)
        {
            ValidateDeviceId(deviceId);
            ComponentPointer bundle = RequireComponents(true);
            WithOperationLock(delegate
            {
                CleanupWorkers();
                Directory.CreateDirectory(Path.Combine(paths.PlayerRoot, "portable_config"));
                string tone = Path.Combine(paths.PlayerRoot, "speaker-test-" + Guid.NewGuid().ToString("N") + ".wav");
                PlaybackWorker worker = null;
                try
                {
                    WriteTestTone(tone);
                    worker = StartPlayback(bundle, tone, 5, true, deviceId, 70, false);
                    if (!worker.Process.WaitForExit(12000)) throw new InvalidOperationException("The speaker test did not finish. Press Stop and check the selected output.");
                    worker.Process.WaitForExit();
                    if (worker.Process.ExitCode != 0) throw new InvalidOperationException("The selected speaker could not play the test tone. " + worker.Output.Text);
                }
                finally
                {
                    if (worker != null && worker.Process.HasExited) { worker.Process.Dispose(); workers.Remove(worker); }
                    try { File.Delete(tone); } catch (IOException) { }
                }
            });
        }

        public void Pause() { Command(new object[] { "cycle", "pause" }, 1000); }
        public void Next() { Command(new object[] { "playlist-next", "force" }, 1000); }

        public void Stop()
        {
            if (!Directory.Exists(paths.PlayerRoot)) return;
            string radio = Path.Combine(paths.EngineRoot, "Radio.ps1");
            if (!File.Exists(radio))
            {
                try { Command(new object[] { "quit" }, 1000); } catch (IOException) { }
                return;
            }
            var args = PowerShellArguments(radio);
            args.AddRange(new string[] { "-MpvFolder", paths.PlayerRoot, "-Stop" });
            RunTool(PowerShellPath(), args, paths.PlayerRoot, null, 20000, null);
        }

        public PlaybackStatus GetStatus()
        {
            try
            {
                object title = Command(new object[] { "get_property", "media-title" }, 150);
                bool paused = Convert.ToBoolean(Command(new object[] { "get_property", "pause" }, 150), CultureInfo.InvariantCulture);
                return new PlaybackStatus { Playing = true, Paused = paused, Title = Convert.ToString(title, CultureInfo.InvariantCulture), Message = paused ? "Paused" : "Playing" };
            }
            catch (Exception error)
            {
                if (!(error is TimeoutException) && !(error is IOException) && !(error is InvalidOperationException)) throw;
                return new PlaybackStatus { Playing = false, Paused = false, Title = "", Message = "Stopped" };
            }
        }

        public void RemoveOwnedTasks()
        {
            WithOperationLock(delegate
            {
                using (IScheduleStore store = new WindowsScheduleStore(userSid, paths.ExecutablePath))
                {
                    store.Snapshot(); // Verify both tasks before removing either one.
                    foreach (string key in SessionKeys) store.Set(key, null);
                }
            });
        }

        public void LogError(Exception error)
        {
            try
            {
                Directory.CreateDirectory(paths.DataRoot);
                using (var gate = new Mutex(false, "AutomaticMusic.Log." + RadioKey(paths.DataRoot)))
                {
                    bool owns;
                    try { owns = gate.WaitOne(2000); } catch (AbandonedMutexException) { owns = true; }
                    if (!owns) return;
                    try
                    {
                        if (File.Exists(paths.LogPath) && new FileInfo(paths.LogPath).Length > 256 * 1024)
                        {
                            string previous = paths.LogPath + ".previous";
                            if (File.Exists(previous)) File.Delete(previous);
                            File.Move(paths.LogPath, previous);
                        }
                        string detail = error.ToString();
                        if (detail.Length > 16000) detail = detail.Substring(0, 16000);
                        File.AppendAllText(paths.LogPath, DateTimeOffset.Now.ToString("u") + Environment.NewLine + detail + Environment.NewLine, Utf8);
                    }
                    finally { gate.ReleaseMutex(); }
                }
            }
            catch { /* Logging must not hide the original error. */ }
        }

        private void PreparePlaybackConfig(AppSettings settings)
        {
            string config = Path.Combine(paths.PlayerRoot, "portable_config");
            string mpv = Path.Combine(config, "mpv.conf");
            string options = Path.Combine(config, "script-opts", "random-start.conf");
            AtomicWrite(mpv, MergeMpvSettings(File.Exists(mpv) ? File.ReadAllBytes(mpv) : null, settings));
            AtomicWrite(options, MergeSamplingSettings(File.Exists(options) ? File.ReadAllBytes(options) : null, settings));
        }

        private PlaybackWorker StartPlayback(ComponentPointer bundle, string source, int seconds, bool manual, string device, int volume, bool acknowledge)
        {
            string radio = Path.Combine(paths.EngineRoot, "Radio.ps1");
            string lua = Path.Combine(paths.EngineRoot, "portable_config", "scripts", "random-start.lua");
            if (!File.Exists(radio) || (!manual && !File.Exists(lua))) throw new InvalidOperationException("The playback engine is missing. Reinstall Automatic Music.");
            Directory.CreateDirectory(paths.PlayerRoot);
            object previousPid = null;
            try { previousPid = Command(new object[] { "get_property", "pid" }, 150); } catch (Exception error) { if (!(error is IOException) && !(error is TimeoutException) && !(error is InvalidOperationException)) throw; }
            var args = PowerShellArguments(radio);
            args.AddRange(new string[] { "-MpvFolder", paths.PlayerRoot, "-MpvExecutable", Path.Combine(bundle.directory, "mpv.exe"),
                "-LuaScriptPath", lua, "-Playlist", source, "-DurationSeconds", seconds.ToString(CultureInfo.InvariantCulture),
                "-AudioDeviceId", device, "-Volume", volume.ToString(CultureInfo.InvariantCulture) });
            if (manual) args.Add("-Manual");
            var output = new LimitedOutput(32768);
            Process process = StartProcess(PowerShellPath(), args, paths.PlayerRoot, bundle.directory, output, null);
            var worker = new PlaybackWorker(process, output);
            workers.Add(worker);
            if (!acknowledge) return worker;
            Stopwatch clock = Stopwatch.StartNew();
            while (clock.ElapsedMilliseconds < 35000)
            {
                if (process.HasExited)
                {
                    process.WaitForExit();
                    throw new InvalidOperationException("Playback could not start. Check the playlist and speaker. " + output.Text);
                }
                try
                {
                    object currentPid = Command(new object[] { "get_property", "pid" }, 300);
                    object position = Command(new object[] { "get_property", "time-pos" }, 300);
                    if (!Object.Equals(currentPid, previousPid) && position != null && Convert.ToDouble(position, CultureInfo.InvariantCulture) >= 0) return worker;
                }
                catch (Exception error) { if (!(error is IOException) && !(error is TimeoutException) && !(error is InvalidOperationException)) throw; }
                Thread.Sleep(150);
            }
            // Leave the bounded session available to Stop; a slow connection may
            // still finish loading, and we never kill a different player's PID.
            throw new InvalidOperationException("Music has not started within 35 seconds. Check your internet connection, playlist access and selected speaker. Press Stop before trying again.");
        }

        private void CleanupWorkers()
        {
            for (int index = workers.Count - 1; index >= 0; index--)
            {
                PlaybackWorker worker = workers[index];
                if (!worker.Process.HasExited) continue;
                worker.Process.WaitForExit();
                if (worker.Process.ExitCode != 0) LogError(new InvalidOperationException("Playback supervisor: " + worker.Output.Text));
                worker.Process.Dispose();
                workers.RemoveAt(index);
            }
        }

        private object Command(object[] command, int timeout)
        {
            using (var pipe = new NamedPipeClientStream(".", endpoint, PipeDirection.InOut, PipeOptions.Asynchronous))
            {
                pipe.Connect(timeout);
                var reader = new StreamReader(pipe, Utf8);
                var writer = new StreamWriter(pipe, Utf8) { AutoFlush = true };
                writer.WriteLine(Serializer().Serialize(new Dictionary<string, object> { { "command", command }, { "request_id", 1 } }));
                if ((string)command[0] == "quit") return null;
                Stopwatch clock = Stopwatch.StartNew();
                while (clock.ElapsedMilliseconds < timeout)
                {
                    Task<string> pending = reader.ReadLineAsync();
                    try { if (!pending.Wait(Math.Max(1, timeout - (int)clock.ElapsedMilliseconds))) throw new TimeoutException("The player did not respond."); }
                    catch (AggregateException error) { throw new IOException("The player connection closed.", error.GetBaseException()); }
                    if (pending.Result == null) throw new IOException("The player disconnected.");
                    var reply = Serializer().Deserialize<Dictionary<string, object>>(pending.Result);
                    object request;
                    if (!reply.TryGetValue("request_id", out request) || Convert.ToInt32(request, CultureInfo.InvariantCulture) != 1) continue;
                    object failure;
                    if (!reply.TryGetValue("error", out failure) || Convert.ToString(failure, CultureInfo.InvariantCulture) != "success")
                        throw new InvalidOperationException("Player: " + Convert.ToString(failure, CultureInfo.InvariantCulture));
                    object value;
                    return reply.TryGetValue("data", out value) ? value : null;
                }
                throw new TimeoutException("The player did not respond.");
            }
        }

        private void WithOperationLock(Action action)
        {
            using (var mutex = new Mutex(false, operationMutex))
            {
                bool owns;
                try { owns = mutex.WaitOne(45000); } catch (AbandonedMutexException) { owns = true; }
                if (!owns) throw new InvalidOperationException("Another Automatic Music operation is still running. Wait a moment and try again.");
                try { action(); } finally { mutex.ReleaseMutex(); }
            }
        }

        private ComponentPointer RequireComponents(bool verifyHashes)
        {
            if (!File.Exists(paths.ComponentsPath)) throw new InvalidOperationException("Install playback components to get started.");
            ComponentPointer pointer = Serializer().Deserialize<ComponentPointer>(ReadText(paths.ComponentsPath, 1024 * 1024));
            if (pointer == null || pointer.schema != 1 || String.IsNullOrEmpty(pointer.bundle) || pointer.versions == null || String.IsNullOrEmpty(pointer.directory))
                throw new InvalidOperationException("The component receipt is invalid. Choose Repair components.");
            pointer.directory = Path.GetFullPath(pointer.directory);
            string componentRoot = Path.Combine(paths.DataRoot, "Components");
            RequireContainedPath(componentRoot, pointer.directory);
            RejectReparsePath(paths.DataRoot, pointer.directory);
            string markerPath = Path.Combine(pointer.directory, "bundle.json");
            RejectReparsePath(pointer.directory, markerPath);
            ComponentMarker marker = Serializer().Deserialize<ComponentMarker>(ReadText(markerPath, 4 * 1024 * 1024));
            string lockFile = Path.Combine(paths.InstallRoot, "components.lock.json");
            if (marker == null || marker.schema != 1 || marker.bundle != pointer.bundle || marker.files == null || !File.Exists(lockFile) ||
                !String.Equals(marker.manifestSha256, FileHash(lockFile), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Installed components do not match this app version. Choose Install or Repair components.");
            if (marker.versions == null || String.IsNullOrEmpty(pointer.versions.mpv) || String.IsNullOrEmpty(pointer.versions.ytDlp) || String.IsNullOrEmpty(pointer.versions.deno) ||
                pointer.versions.mpv != marker.versions.mpv || pointer.versions.ytDlp != marker.versions.ytDlp || pointer.versions.deno != marker.versions.deno ||
                marker.files.Count > 4096 || marker.files.Any(delegate(ComponentFile file) { return file == null; }))
                throw new InvalidOperationException("The component receipt does not match its bundle. Choose Repair components.");
            foreach (string name in RequiredComponents)
            {
                List<ComponentFile> matches = marker.files.Where(delegate(ComponentFile file) { return String.Equals(file.path, name, StringComparison.OrdinalIgnoreCase); }).ToList();
                string executable = Path.Combine(pointer.directory, name);
                RejectReparsePath(pointer.directory, executable);
                if (matches.Count != 1 || !File.Exists(executable) || matches[0].length != new FileInfo(executable).Length ||
                    !Regex.IsMatch(matches[0].sha256 ?? "", "^[a-fA-F0-9]{64}$") ||
                    matches[0].length <= 0)
                    throw new InvalidOperationException("A playback component is missing or has changed (" + name + "). Choose Repair components.");
            }
            if (verifyHashes)
            {
                var expected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (ComponentFile file in marker.files)
                {
                    string relative = (file.path ?? "").Replace('/', Path.DirectorySeparatorChar);
                    if (String.IsNullOrEmpty(relative) || Path.IsPathRooted(relative) || relative.Split(Path.DirectorySeparatorChar).Any(delegate(string part) { return part == ".." || part == "." || part.Length == 0; }) || !expected.Add(relative))
                        throw new InvalidOperationException("The component receipt contains an invalid file path. Choose Repair components.");
                    string full = Path.GetFullPath(Path.Combine(pointer.directory, relative));
                    RequireContainedPath(pointer.directory, full); RejectReparsePath(pointer.directory, full);
                    if (!File.Exists(full) || new FileInfo(full).Length != file.length || !String.Equals(FileHash(full), file.sha256, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("An installed component file has changed. Choose Repair components.");
                }
                var pending = new Stack<string>(); pending.Push(pointer.directory);
                while (pending.Count > 0)
                {
                    string directory = pending.Pop();
                    foreach (string child in Directory.GetDirectories(directory)) { RejectReparsePath(pointer.directory, child); pending.Push(child); }
                    foreach (string file in Directory.GetFiles(directory))
                    {
                        RejectReparsePath(pointer.directory, file);
                        if (String.Equals(file, markerPath, StringComparison.OrdinalIgnoreCase)) continue;
                        string relative = file.Substring(pointer.directory.TrimEnd(Path.DirectorySeparatorChar).Length + 1);
                        if (!expected.Contains(relative)) throw new InvalidOperationException("An unexpected file was found beside the playback components. Choose Repair components.");
                    }
                }
            }
            return pointer;
        }

        internal static void RequireContainedPath(string parent, string child)
        {
            string prefix = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!Path.GetFullPath(child).StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The component location is outside this app's component folder. Choose Repair components.");
        }

        private static void RejectReparsePath(string parent, string child)
        {
            string boundary = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar);
            string current = Path.GetFullPath(child);
            while (current.Length >= boundary.Length)
            {
                if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidOperationException("A component path is a link or junction. Choose a normal local app folder and reinstall the components.");
                if (String.Equals(current, boundary, StringComparison.OrdinalIgnoreCase)) break;
                current = Path.GetDirectoryName(current);
                if (String.IsNullOrEmpty(current)) break;
            }
        }

        internal static string NormalizePlaylistUrl(string text)
        {
            string input = (text ?? "").Trim();
            Uri uri;
            string[] hosts = { "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be" };
            if (input.Length == 0 || input.Length > 4096 || Regex.IsMatch(input, "[\\s\\\"<>|\\x00]") ||
                !Uri.TryCreate(input, UriKind.Absolute, out uri) || (uri.Scheme != "https" && uri.Scheme != "http") ||
                !String.IsNullOrEmpty(uri.UserInfo) || !uri.IsDefaultPort || !hosts.Contains(uri.DnsSafeHost.ToLowerInvariant()))
                throw new ArgumentException("Paste one complete YouTube playlist link, with no quotes or extra text.");
            string id = null;
            foreach (string pair in uri.Query.TrimStart('?').Split('&'))
            {
                int equals = pair.IndexOf('=');
                if (equals < 0 || Uri.UnescapeDataString(pair.Substring(0, equals)) != "list") continue;
                if (id != null) throw new ArgumentException("The link contains more than one playlist. Copy the playlist's Share link again.");
                id = Uri.UnescapeDataString(pair.Substring(equals + 1));
            }
            if (id == null || !Regex.IsMatch(id, "^[A-Za-z0-9_-]{2,200}$"))
                throw new ArgumentException("Use a YouTube playlist link containing list=, rather than a single video link.");
            return "https://www.youtube.com/playlist?list=" + id;
        }

        internal static void ValidateSettings(AppSettings settings)
        {
            if (settings == null || settings.Schema != 1) throw new ArgumentException("The settings format is not supported.");
            ValidateDeviceId(settings.AudioDeviceId);
            if (settings.Volume < 0 || settings.Volume > 100) throw new ArgumentException("Volume must be between 0 and 100.");
            CheckRange(settings.CutoffMinutes, 0.01, 1440, "Long recording cutoff");
            CheckRange(settings.SampleMinMinutes, 0.01, 1440, "Minimum sample length");
            CheckRange(settings.SampleMaxMinutes, 0.01, 1440, "Maximum sample length");
            CheckRange(settings.FadeSeconds, 0, 60, "Fade length");
            if (settings.SampleMinMinutes > settings.SampleMaxMinutes) throw new ArgumentException("The minimum sample length cannot exceed the maximum.");
            foreach (string key in SessionKeys)
            {
                SessionSettings session = settings.GetSession(key);
                if (session == null) throw new ArgumentException("Both session settings must be present.");
                if (!Regex.IsMatch(session.StartTime ?? "", "^([01][0-9]|2[0-3]):[0-5][0-9]$")) throw new ArgumentException("Choose a start time between 00:00 and 23:59.");
                if (session.DurationMinutes < 1 || session.DurationMinutes > 1440) throw new ArgumentException("Session duration must be between 1 minute and 24 hours.");
                if (session.Days == null || (session.Enabled && session.Days.Length == 0) || session.Days.Length > 7 || session.Days.Any(delegate(string day) { return !DayKeys.Contains(day); }) || session.Days.Distinct().Count() != session.Days.Length)
                    throw new ArgumentException("Choose at least one day, without duplicate days.");
                if (!String.IsNullOrWhiteSpace(session.PlaylistUrl)) session.PlaylistUrl = NormalizePlaylistUrl(session.PlaylistUrl);
                else if (session.Enabled) throw new ArgumentException("Paste a playlist before enabling its schedule.");
                else session.PlaylistUrl = "";
            }
        }

        private static void ValidateDeviceId(string value)
        {
            if (String.IsNullOrWhiteSpace(value) || value.Length > 2048 || Regex.IsMatch(value, "[\\x00\\r\\n]"))
                throw new ArgumentException("Choose a valid audio output.");
        }

        private static void CheckRange(double value, double min, double max, string label)
        {
            if (Double.IsNaN(value) || Double.IsInfinity(value) || value < min || value > max)
                throw new ArgumentException(label + " must be between " + min.ToString(CultureInfo.InvariantCulture) + " and " + max.ToString(CultureInfo.InvariantCulture) + ".");
        }

        private static AppSettings CloneSettings(AppSettings settings)
        {
            if (settings == null) throw new ArgumentNullException("settings");
            return Serializer().Deserialize<AppSettings>(Serializer().Serialize(settings));
        }

        internal static byte[] MergeMpvSettings(byte[] previous, AppSettings settings)
        {
            var values = new Dictionary<string, string> { { "audio-device", ConfigValue(settings.AudioDeviceId) }, { "volume", settings.Volume.ToString(CultureInfo.InvariantCulture) } };
            if (previous == null)
                return Utf8.GetBytes("audio-device=" + values["audio-device"] + "\r\nvolume=" + values["volume"] + "\r\nvid=no\r\nytdl-format=bestaudio/best\r\nforce-window=yes\r\n");
            return MergeConfig(previous, values, true);
        }

        internal static byte[] MergeSamplingSettings(byte[] previous, AppSettings settings)
        {
            var values = new Dictionary<string, string> { { "section_mode", settings.SamplingEnabled ? "yes" : "no" },
                { "min_duration_minutes", settings.CutoffMinutes.ToString(CultureInfo.InvariantCulture) },
                { "section_min_minutes", settings.SampleMinMinutes.ToString(CultureInfo.InvariantCulture) },
                { "section_max_minutes", settings.SampleMaxMinutes.ToString(CultureInfo.InvariantCulture) },
                { "fade_seconds", settings.FadeSeconds.ToString(CultureInfo.InvariantCulture) } };
            return MergeConfig(previous ?? new byte[0], values, false);
        }

        internal static string ConfigValue(string value)
        {
            ValidateDeviceId(value);
            return Regex.IsMatch(value, "[#\\\"']|^%|^[ \\t]|[ \\t]$") ? "%" + Utf8.GetByteCount(value).ToString(CultureInfo.InvariantCulture) + "%" + value : value;
        }

        internal static byte[] MergeConfig(byte[] original, IDictionary<string, string> values, bool profiles)
        {
            bool bom = original.Length >= 3 && original[0] == 239 && original[1] == 187 && original[2] == 191;
            int offset = bom ? 3 : 0;
            string text;
            try { text = Utf8.GetString(original, offset, original.Length - offset); }
            catch (DecoderFallbackException error) { throw new InvalidOperationException("The existing player configuration is not valid UTF-8; it was not changed.", error); }
            string newline = Regex.Match(text, "\\r\\n|\\r|\\n").Value;
            if (newline.Length == 0) newline = "\r\n";
            bool global = true;
            var found = new HashSet<string>();
            var result = new StringBuilder();
            foreach (Match match in Regex.Matches(text, "(?<line>[^\\r\\n]*)(?<eol>\\r\\n|\\r|\\n|$)"))
            {
                if (match.Length == 0) continue;
                string line = match.Groups["line"].Value;
                Match profile = Regex.Match(line, @"^[ \t]*\[(?<profile>[^\]\r\n]*)\][ \t]*(?:#.*)?$");
                Match option = Regex.Match(line, @"^(?<prefix>[ \t]*(?:--)?)(?<key>[A-Za-z0-9_-]+)(?<equals>[ \t]*=[ \t]*)(?<value>.*)$");
                if (profiles && profile.Success) global = profile.Groups["profile"].Value == "default" || profile.Groups["profile"].Value == "";
                else if (global && option.Success && values.ContainsKey(option.Groups["key"].Value))
                {
                    string key = option.Groups["key"].Value;
                    line = option.Groups["prefix"].Value + key + option.Groups["equals"].Value + values[key] + ConfigSuffix(option.Groups["value"].Value);
                    found.Add(key);
                }
                result.Append(line).Append(match.Groups["eol"].Value);
            }
            var prefix = new StringBuilder();
            foreach (KeyValuePair<string, string> entry in values)
                if (!found.Contains(entry.Key)) prefix.Append(entry.Key).Append('=').Append(entry.Value).Append(newline);
            byte[] bytes = Utf8.GetBytes(prefix.ToString() + result.ToString());
            if (!bom) return bytes;
            byte[] output = new byte[bytes.Length + 3];
            output[0] = 239; output[1] = 187; output[2] = 191;
            Buffer.BlockCopy(bytes, 0, output, 3, bytes.Length);
            return output;
        }

        private static string ConfigSuffix(string value)
        {
            string suffix;
            if (value.StartsWith("\"") || value.StartsWith("'"))
            {
                int end = value.IndexOf(value[0], 1);
                if (end < 0) throw new InvalidOperationException("An existing configuration value has an unclosed quote; it was not changed.");
                suffix = value.Substring(end + 1);
            }
            else
            {
                Match length = Regex.Match(value, @"^%(?<count>[0-9]+)%");
                if (!length.Success) return Regex.Match(value, @"[ \t]*(?:#.*)?$").Value;
                int count;
                byte[] bytes = Utf8.GetBytes(value.Substring(length.Length));
                if (!Int32.TryParse(length.Groups["count"].Value, out count) || count > bytes.Length)
                    throw new InvalidOperationException("An existing configuration value is truncated; it was not changed.");
                suffix = Utf8.GetString(bytes, count, bytes.Length - count);
            }
            if (!Regex.IsMatch(suffix, @"^[ \t]*(?:#.*)?$")) throw new InvalidOperationException("Unexpected text follows an existing configuration value; it was not changed.");
            return suffix;
        }

        internal static string BuildTaskXml(SessionSettings session, string key, bool wake, string sid, string executable)
        {
            if (!SessionKeys.Contains(key)) throw new ArgumentException("Unknown session.");
            var text = new StringBuilder();
            var settings = new XmlWriterSettings { OmitXmlDeclaration = true, Indent = true };
            using (XmlWriter xml = XmlWriter.Create(text, settings))
            {
                xml.WriteStartElement("Task", "http://schemas.microsoft.com/windows/2004/02/mit/task");
                xml.WriteAttributeString("version", "1.2");
                xml.WriteStartElement("RegistrationInfo"); xml.WriteElementString("Description", TaskDescription(sid, key)); xml.WriteEndElement();
                xml.WriteStartElement("Triggers"); xml.WriteStartElement("CalendarTrigger");
                xml.WriteElementString("StartBoundary", DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + "T" + session.StartTime + ":00");
                xml.WriteElementString("Enabled", "true"); xml.WriteStartElement("ScheduleByWeek"); xml.WriteElementString("WeeksInterval", "1"); xml.WriteStartElement("DaysOfWeek");
                for (int i = 0; i < DayKeys.Length; i++) if (session.Days.Contains(DayKeys[i])) xml.WriteElementString(DayNames[i], "");
                xml.WriteEndElement(); xml.WriteEndElement(); xml.WriteEndElement(); xml.WriteEndElement();
                xml.WriteStartElement("Principals"); xml.WriteStartElement("Principal"); xml.WriteAttributeString("id", "Listener");
                xml.WriteElementString("UserId", sid); xml.WriteElementString("LogonType", "InteractiveToken"); xml.WriteElementString("RunLevel", "LeastPrivilege"); xml.WriteEndElement(); xml.WriteEndElement();
                xml.WriteStartElement("Settings"); xml.WriteElementString("MultipleInstancesPolicy", "IgnoreNew");
                xml.WriteElementString("DisallowStartIfOnBatteries", "false"); xml.WriteElementString("StopIfGoingOnBatteries", "false");
                xml.WriteElementString("StartWhenAvailable", "false"); xml.WriteElementString("AllowStartOnDemand", "true");
                xml.WriteElementString("Enabled", "true"); xml.WriteElementString("WakeToRun", wake ? "true" : "false");
                xml.WriteElementString("ExecutionTimeLimit", XmlConvert.ToString(TimeSpan.FromMinutes(session.DurationMinutes + 1)));
                xml.WriteEndElement();
                xml.WriteStartElement("Actions"); xml.WriteAttributeString("Context", "Listener"); xml.WriteStartElement("Exec");
                xml.WriteElementString("Command", executable); xml.WriteElementString("Arguments", "--run-session " + key);
                xml.WriteElementString("WorkingDirectory", Path.GetDirectoryName(executable)); xml.WriteEndElement(); xml.WriteEndElement(); xml.WriteEndElement();
            }
            return text.ToString();
        }

        internal static string TaskDescription(string sid, string key) { return "Automatic Music managed session; schema=1; user=" + sid + "; session=" + key; }

        internal static void ValidateTaskOwnership(string xmlText, string key, string sid, string executable)
        {
            var document = new XmlDocument { XmlResolver = null };
            using (var reader = XmlReader.Create(new StringReader(xmlText), new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 1024 * 1024 })) document.Load(reader);
            var namespaces = new XmlNamespaceManager(document.NameTable); namespaces.AddNamespace("t", "http://schemas.microsoft.com/windows/2004/02/mit/task");
            Func<string, string> value = delegate(string path) { XmlNode node = document.SelectSingleNode(path, namespaces); return node == null ? "" : node.InnerText; };
            XmlNodeList actions = document.SelectNodes("/t:Task/t:Actions/*", namespaces);
            if (value("/t:Task/t:RegistrationInfo/t:Description") != TaskDescription(sid, key) || actions.Count != 1 || actions[0].LocalName != "Exec" ||
                !String.Equals(value("/t:Task/t:Actions/t:Exec/t:Command"), executable, StringComparison.OrdinalIgnoreCase) ||
                value("/t:Task/t:Actions/t:Exec/t:Arguments") != "--run-session " + key ||
                !SameWindowsUser(value("/t:Task/t:Principals/t:Principal/t:UserId"), sid))
                throw new InvalidOperationException("An existing task named " + key + " is not owned by this app installation. It has been left unchanged.");
        }

        private static bool SameWindowsUser(string value, string sid)
        {
            if (value == sid) return true;
            try { return ((SecurityIdentifier)new NTAccount(value).Translate(typeof(SecurityIdentifier))).Value == sid; }
            catch (IdentityNotMappedException) { return false; }
            catch (ArgumentException) { return false; }
        }

        internal static void CommitSettings(IScheduleStore store, IList<FileUpdate> updates, IDictionary<string, string> desiredTasks)
        {
            Dictionary<string, string> oldTasks = store.Snapshot();
            var before = new List<FileUpdate>();
            foreach (FileUpdate update in updates)
            {
                if (Directory.Exists(update.Path)) throw new IOException("A settings path is a directory: " + update.Path);
                before.Add(new FileUpdate(update.Path, File.Exists(update.Path) ? File.ReadAllBytes(update.Path) : null));
            }
            try
            {
                for (int i = 0; i < updates.Count - 1; i++) AtomicWrite(updates[i].Path, updates[i].Bytes);
                foreach (string key in SessionKeys) store.Set(key, desiredTasks[key]);
                AtomicWrite(updates[updates.Count - 1].Path, updates[updates.Count - 1].Bytes);
            }
            catch (Exception error)
            {
                var rollbackFailures = new List<string>();
                foreach (string key in SessionKeys)
                    try { store.Set(key, oldTasks[key]); } catch (Exception restore) { rollbackFailures.Add("task " + key + ": " + restore.Message); }
                foreach (FileUpdate original in before)
                    try { if (original.Bytes == null) { if (File.Exists(original.Path)) File.Delete(original.Path); } else AtomicWrite(original.Path, original.Bytes); }
                    catch (Exception restore) { rollbackFailures.Add("settings: " + restore.Message); }
                throw new InvalidOperationException("Settings were not saved. " + error.Message + (rollbackFailures.Count == 0 ? " Previous settings and schedules were restored." : " Some rollback steps failed: " + String.Join("; ", rollbackFailures)), error);
            }
        }

        internal static void AtomicWrite(string path, byte[] bytes)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            if (File.Exists(path) && File.ReadAllBytes(path).SequenceEqual(bytes)) return;
            string temporary = path + ".new-" + Guid.NewGuid().ToString("N");
            try
            {
                File.WriteAllBytes(temporary, bytes);
                if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }

        private static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024, RecursionLimit = 64 }; }
        private static string ReadText(string path, int maximum)
        {
            if (!File.Exists(path)) throw new InvalidOperationException("A required app file is missing: " + Path.GetFileName(path) + ". Choose Repair components.");
            if (new FileInfo(path).Length > maximum) throw new InvalidOperationException("An app settings file is too large: " + Path.GetFileName(path));
            return File.ReadAllText(path, Utf8);
        }
        private static string FileHash(string path) { using (SHA256 hash = SHA256.Create()) using (FileStream file = File.OpenRead(path)) return BitConverter.ToString(hash.ComputeHash(file)).Replace("-", "").ToLowerInvariant(); }
        internal static string RadioKey(string folder) { using (SHA256 hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(Utf8.GetBytes(Path.GetFullPath(folder).TrimEnd('\\', '/').ToLowerInvariant()))).Replace("-", "").Substring(0, 20); }
        internal static string QuoteArgument(string value)
        {
            if (value == null) value = "";
            string escaped = Regex.Replace(value, "(\\\\*)\"", "$1$1\\\"");
            return "\"" + Regex.Replace(escaped, "(\\\\+)$", "$1$1") + "\"";
        }
        private static string PowerShellPath() { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"); }
        private static List<string> PowerShellArguments(string script) { return new List<string> { "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script }; }

        private static Process StartProcess(string executable, IEnumerable<string> arguments, string working, string componentPath, LimitedOutput output, Action<string> progress)
        {
            var start = new ProcessStartInfo(executable, String.Join(" ", arguments.Select(QuoteArgument))) { WorkingDirectory = working, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
            if (!String.IsNullOrEmpty(componentPath)) start.EnvironmentVariables["PATH"] = componentPath + ";" + (start.EnvironmentVariables["PATH"] ?? "");
            var process = new Process { StartInfo = start };
            DataReceivedEventHandler capture = delegate(object sender, DataReceivedEventArgs e) { if (e.Data == null) return; output.Add(e.Data); if (progress != null) progress(e.Data); };
            process.OutputDataReceived += capture; process.ErrorDataReceived += capture;
            try { process.Start(); process.StandardInput.Close(); process.BeginOutputReadLine(); process.BeginErrorReadLine(); return process; }
            catch { process.Dispose(); throw; }
        }

        private static string RunTool(string executable, IEnumerable<string> arguments, string working, string componentPath, int timeout, Action<string> progress)
        {
            var output = new LimitedOutput(1024 * 1024);
            using (Process process = StartProcess(executable, arguments, working, componentPath, output, progress))
            {
                if (!process.WaitForExit(timeout))
                {
                    try { process.Kill(); process.WaitForExit(5000); } catch (InvalidOperationException) { }
                    throw new TimeoutException("The operation took too long. Check the connection and try again.");
                }
                process.WaitForExit();
                if (process.ExitCode != 0) throw new InvalidOperationException("The operation failed (exit " + process.ExitCode.ToString(CultureInfo.InvariantCulture) + "). " + output.Tail(6000));
                return output.Text;
            }
        }

        private static void WriteTestTone(string path)
        {
            const int rate = 44100, samples = 44100;
            using (var writer = new BinaryWriter(File.Create(path)))
            {
                writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + samples * 2); writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
                writer.Write(16); writer.Write((short)1); writer.Write((short)1); writer.Write(rate); writer.Write(rate * 2); writer.Write((short)2); writer.Write((short)16);
                writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(samples * 2);
                for (int i = 0; i < samples; i++)
                {
                    double ramp = Math.Min(1, Math.Min(i / 2205.0, (samples - i) / 2205.0));
                    writer.Write((short)(Math.Sin(2 * Math.PI * 440 * i / rate) * 6000 * ramp));
                }
            }
        }

        private sealed class PlaybackWorker { public readonly Process Process; public readonly LimitedOutput Output; public PlaybackWorker(Process process, LimitedOutput output) { Process = process; Output = output; } }
        private sealed class LimitedOutput
        {
            private readonly int maximum; private readonly StringBuilder text = new StringBuilder();
            public LimitedOutput(int limit) { maximum = limit; }
            public void Add(string line) { lock (text) { text.AppendLine(line); if (text.Length > maximum) text.Remove(0, text.Length - maximum); } }
            public string Text { get { lock (text) return text.ToString(); } }
            public string Tail(int count) { string value = Text; return value.Length > count ? value.Substring(value.Length - count) : value; }
        }
        private sealed class ComponentPointer { public int schema { get; set; } public string bundle { get; set; } public string directory { get; set; } public ComponentVersions versions { get; set; } }
        private sealed class ComponentVersions { public string mpv { get; set; } public string ytDlp { get; set; } public string deno { get; set; } }
        private sealed class ComponentMarker { public int schema { get; set; } public string bundle { get; set; } public string manifestSha256 { get; set; } public ComponentVersions versions { get; set; } public List<ComponentFile> files { get; set; } }
        private sealed class ComponentFile { public string path { get; set; } public long length { get; set; } public string sha256 { get; set; } }
    }

    internal sealed class FileUpdate { public readonly string Path; public readonly byte[] Bytes; public FileUpdate(string path, byte[] bytes) { Path = path; Bytes = bytes; } }
    internal interface IScheduleStore : IDisposable { Dictionary<string, string> Snapshot(); void Set(string key, string xml); }

    internal sealed class WindowsScheduleStore : IScheduleStore
    {
        private readonly string sid, executable, folderPath;
        private dynamic service;
        public WindowsScheduleStore(string userSid, string executablePath)
            : this(userSid, executablePath, null) { }
        internal WindowsScheduleStore(string userSid, string executablePath, string testSuffix)
        {
            sid = userSid; executable = executablePath;
            if (testSuffix != null && !Regex.IsMatch(testSuffix, "^[a-f0-9]{32}$")) throw new ArgumentException("Invalid scheduler test identifier.");
            folderPath = testSuffix == null ? "\\AutomaticMusic-" + sid : "\\AutomaticMusic-Test-" + sid + "-" + testSuffix;
            service = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service", true)); service.Connect();
        }
        public Dictionary<string, string> Snapshot()
        {
            var result = new Dictionary<string, string>();
            foreach (string key in new string[] { "morning", "finisher" }) result[key] = Read(key);
            return result;
        }
        private string Read(string key)
        {
            dynamic folder = null, task = null;
            try
            {
                folder = service.GetFolder(folderPath); task = folder.GetTask(key); string xml = task.Xml;
                RadioBackend.ValidateTaskOwnership(xml, key, sid, executable); return xml;
            }
            catch (Exception error) { if (Missing(error)) return null; throw; }
            finally { Release(task); Release(folder); }
        }
        public void Set(string key, string xml)
        {
            if (key != "morning" && key != "finisher") throw new ArgumentException("Unknown managed task.");
            string previous = Read(key); // Refuse a foreign task even during rollback.
            if (previous == null && xml == null) return;
            if (xml != null) RadioBackend.ValidateTaskOwnership(xml, key, sid, executable);
            dynamic folder = null, root = null, saved = null;
            try
            {
                try { folder = service.GetFolder(folderPath); }
                catch (Exception error)
                {
                    if (!Missing(error)) throw;
                    root = service.GetFolder("\\"); folder = root.CreateFolder(folderPath.TrimStart('\\'), null);
                }
                if (xml == null) folder.DeleteTask(key, 0);
                else saved = folder.RegisterTask(key, xml, 6, sid, null, 3, null);
            }
            finally { Release(saved); Release(folder); Release(root); }
        }
        // Dynamic COM interop translates some HRESULTs into framework exception
        // types (notably FileNotFoundException), rather than COMException.
        // Only the two absence codes are harmless; access denied must propagate.
        private static bool Missing(Exception error) { return error.HResult == unchecked((int)0x80070002) || error.HResult == unchecked((int)0x80070003); }
        internal void RemoveEmptyTestFolder()
        {
            if (!folderPath.StartsWith("\\AutomaticMusic-Test-", StringComparison.Ordinal)) throw new InvalidOperationException("Only a test folder can be removed here.");
            dynamic folder = null, tasks = null, folders = null, root = null;
            try
            {
                try { folder = service.GetFolder(folderPath); } catch (Exception error) { if (Missing(error)) return; throw; }
                tasks = folder.GetTasks(0); folders = folder.GetFolders(0);
                if (tasks.Count != 0 || folders.Count != 0) throw new InvalidOperationException("The scheduler test folder is not empty.");
                root = service.GetFolder("\\"); root.DeleteFolder(folderPath.TrimStart('\\'), 0);
            }
            finally { Release(root); Release(folders); Release(tasks); Release(folder); }
        }
        private static void Release(object value) { if (value != null && Marshal.IsComObject(value)) Marshal.FinalReleaseComObject(value); }
        public void Dispose() { Release(service); service = null; }
    }
}
