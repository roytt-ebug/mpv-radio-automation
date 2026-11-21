using System;
using System.Collections.Generic;
using System.IO;

namespace AutomaticMusic
{
    public static class Product
    {
        public const string Name = "Automatic Music";
        public const string Version = "0.2.0-beta.1";
        public const string WindowMutex = "AutomaticMusic.Desktop";
    }

    public sealed class AppPaths
    {
        public string InstallRoot { get; private set; }
        public string DataRoot { get; private set; }
        public string PlayerRoot { get { return Path.Combine(DataRoot, "Player"); } }
        public string EngineRoot { get { return Path.Combine(InstallRoot, "engine"); } }
        public string SettingsPath { get { return Path.Combine(DataRoot, "settings.json"); } }
        public string ComponentsPath { get { return Path.Combine(DataRoot, "components.json"); } }
        public string ExecutablePath { get { return Path.Combine(InstallRoot, "AutomaticMusic.exe"); } }
        public string LogPath { get { return Path.Combine(DataRoot, "app.log"); } }

        public AppPaths(string installRoot, string dataRoot)
        {
            InstallRoot = Path.GetFullPath(installRoot).TrimEnd(Path.DirectorySeparatorChar);
            DataRoot = Path.GetFullPath(dataRoot).TrimEnd(Path.DirectorySeparatorChar);
        }

        public static AppPaths CreateDefault()
        {
            return new AppPaths(AppDomain.CurrentDomain.BaseDirectory,
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Product.Name));
        }
    }

    public sealed class AppSettings
    {
        public int Schema { get; set; }
        public string AudioDeviceId { get; set; }
        public int Volume { get; set; }
        public bool SamplingEnabled { get; set; }
        public double CutoffMinutes { get; set; }
        public double SampleMinMinutes { get; set; }
        public double SampleMaxMinutes { get; set; }
        public double FadeSeconds { get; set; }
        public bool WakeComputer { get; set; }
        public SessionSettings Morning { get; set; }
        public SessionSettings Finisher { get; set; }

        public AppSettings()
        {
            Schema = 1;
            AudioDeviceId = "auto";
            Volume = 70;
            SamplingEnabled = true;
            CutoffMinutes = 15;
            SampleMinMinutes = 10;
            SampleMaxMinutes = 30;
            FadeSeconds = 5;
            Morning = new SessionSettings { StartTime = "06:45", Days = new string[] { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" } };
            Finisher = new SessionSettings { StartTime = "15:45", Days = new string[] { "Mon", "Tue", "Wed", "Thu", "Fri" } };
        }

        public SessionSettings GetSession(string key)
        {
            if (key == "morning") return Morning;
            if (key == "finisher") return Finisher;
            throw new ArgumentException("Choose Morning or Day Finisher.");
        }
    }

    public sealed class SessionSettings
    {
        public bool Enabled { get; set; }
        public string PlaylistUrl { get; set; }
        public string StartTime { get; set; }
        public string[] Days { get; set; }
        public int DurationMinutes { get; set; }

        public SessionSettings()
        {
            Enabled = false;
            PlaylistUrl = "";
            StartTime = "06:45";
            Days = new string[] { "Mon", "Tue", "Wed", "Thu", "Fri" };
            DurationMinutes = 180;
        }
    }

    public sealed class AudioDeviceInfo
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public override string ToString() { return Name; }
    }

    public sealed class ComponentStatus
    {
        public bool Ready { get; set; }
        public string Message { get; set; }
        public string Bundle { get; set; }
        public string Directory { get; set; }
        public string MpvVersion { get; set; }
        public string YtDlpVersion { get; set; }
        public string DenoVersion { get; set; }
    }

    public sealed class PlaylistVerification
    {
        public string Url { get; set; }
        public string Title { get; set; }
        public string Message { get; set; }
    }

    public sealed class PlaybackStatus
    {
        public bool Playing { get; set; }
        public bool Paused { get; set; }
        public string Title { get; set; }
        public string Message { get; set; }
    }
}
