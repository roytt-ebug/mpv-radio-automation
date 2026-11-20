using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace AutomaticMusic
{
    public sealed class MainForm : Form
    {
        private static readonly Color Ink = Color.FromArgb(29, 44, 59);
        private static readonly Color SecondaryInk = Color.FromArgb(89, 102, 114);
        private static readonly Color Canvas = Color.FromArgb(248, 249, 247);
        private static readonly Color Paper = Color.White;
        private static readonly Color Accent = Color.FromArgb(25, 104, 131);
        private static readonly Color AccentSoft = Color.FromArgb(227, 240, 243);
        private static readonly Color Line = Color.FromArgb(218, 225, 227);
        private static readonly Color ErrorInk = Color.FromArgb(157, 43, 48);
        private readonly RadioBackend backend;
        private readonly AppPaths paths;
        private AppSettings settings;
        private readonly bool preview;
        private readonly bool setupPreview;
        private bool busy;
        private bool refreshing;
        private bool loading;
        private bool componentsReady;
        private bool playing;
        private bool allowExit;
        private string selectedSession = "morning";
        private string currentPage = "setup";
        private readonly Dictionary<string, Panel> pages = new Dictionary<string, Panel>();
        private readonly Dictionary<string, Button> navigation = new Dictionary<string, Button>();
        private readonly List<CheckBox> dayChecks = new List<CheckBox>();
        private readonly Timer statusTimer = new Timer();
        private Panel content;
        private Panel sidebar;
        private TableLayoutPanel shell;
        private Button setupNav;
        private Button musicNav;
        private Button advancedNav;
        private Label footerStatus;
        private Label footerTitle;
        private Button pauseButton;
        private Button nextButton;
        private Button stopButton;
        private Label setupHeading;
        private Label setupDescription;
        private Label setupStep;
        private Label componentSummary;
        private Label mpvState;
        private Label ytdlpState;
        private Label denoState;
        private Button installButton;
        private Button continueButton;
        private ProgressBar installProgress;
        private TextBox installDetails;
        private Button morningButton;
        private Button finisherButton;
        private TextBox playlist;
        private Button verifyButton;
        private Label playlistResult;
        private ComboBox speaker;
        private Button speakerTestButton;
        private Button refreshSpeakersButton;
        private TrackBar volume;
        private Label volumeLabel;
        private CheckBox scheduleEnabled;
        private FlowLayoutPanel dayRow;
        private DateTimePicker startTime;
        private NumericUpDown durationHours;
        private NumericUpDown durationMinutes;
        private Label scheduleHint;
        private Label saveMessage;
        private Button saveButton;
        private Button playButton;
        private CheckBox samplingEnabled;
        private NumericUpDown cutoff;
        private NumericUpDown sampleMin;
        private NumericUpDown sampleMax;
        private NumericUpDown fade;
        private CheckBox wakeComputer;
        private Button repairButton;
        private Button uninstallButton;
        private Button saveAdvancedButton;

        public MainForm(RadioBackend backend, AppPaths paths, AppSettings settings, bool preview, bool setupPreview)
        {
            this.backend = backend;
            this.paths = paths;
            this.settings = settings;
            this.preview = preview;
            this.setupPreview = setupPreview;
            Text = Product.Name + (preview ? " — interface preview" : "");
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(960, 760);
            MinimumSize = new Size(720, 650);
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);
            ForeColor = Ink;
            BackColor = Canvas;
            try { Icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application; }
            catch { Icon = SystemIcons.Application; }
            BuildWindow();
            LoadSettingsIntoControls();
            ShowPage("setup");
            statusTimer.Interval = 3000;
            statusTimer.Tick += async delegate { await RefreshStatusAsync(); };
            Shown += async delegate
            {
                if (preview)
                {
                    ApplyComponentStatus(new ComponentStatus { Ready = !setupPreview, Message = setupPreview ? "Ready to set up playback" : "Playback components are ready", MpvVersion = "Installed", YtDlpVersion = "Installed", DenoVersion = "Installed" });
                    speaker.Items.Clear();
                    speaker.Items.Add(new AudioDeviceInfo { Id = "auto", Name = "Windows default output" });
                    speaker.Items.Add(new AudioDeviceInfo { Id = "example-usb", Name = "Example speakers (USB audio)" });
                    speaker.SelectedIndex = setupPreview ? 0 : 1;
                    ShowPage(setupPreview ? "setup" : "music");
                    footerStatus.Text = "Interface preview · sample settings";
                    return;
                }
                await InitializeAsync();
                statusTimer.Start();
            };
            FormClosing += HandleFormClosing;
            FormClosed += delegate { statusTimer.Stop(); statusTimer.Dispose(); };
        }

        private void BuildWindow()
        {
            shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3, Margin = Padding.Empty, Padding = Padding.Empty, BackColor = Canvas };
            shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 174));
            shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 82));
            shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 85));
            Controls.Add(shell);

            Panel header = new Panel { Dock = DockStyle.Fill, BackColor = Paper, Padding = new Padding(26, 14, 26, 10) };
            Label brand = MakeLabel("Automatic Music", 22, FontStyle.Bold, Ink);
            brand.Dock = DockStyle.Top;
            brand.Height = 34;
            Label subtitle = MakeLabel("Your playlist. Your speakers. Your schedule.", 10, FontStyle.Regular, SecondaryInk);
            subtitle.Dock = DockStyle.Bottom;
            subtitle.Height = 24;
            header.Controls.Add(brand);
            header.Controls.Add(subtitle);
            shell.Controls.Add(header, 0, 0);
            shell.SetColumnSpan(header, 2);

            sidebar = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(237, 241, 240), Padding = new Padding(14, 22, 12, 12) };
            FlowLayoutPanel navStack = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = Padding.Empty };
            setupNav = NavigationButton("Setup", "setup");
            musicNav = NavigationButton("Music & schedule", "music");
            advancedNav = NavigationButton("Advanced", "advanced");
            navStack.Controls.Add(setupNav);
            navStack.Controls.Add(musicNav);
            navStack.Controls.Add(advancedNav);
            Label sidebarNote = MakeLabel("One player.\r\nA little more variety.", 9, FontStyle.Regular, SecondaryInk);
            sidebarNote.Dock = DockStyle.Bottom;
            sidebarNote.Height = 52;
            sidebar.Controls.Add(navStack);
            sidebar.Controls.Add(sidebarNote);
            shell.Controls.Add(sidebar, 0, 1);

            content = new Panel { Dock = DockStyle.Fill, BackColor = Canvas, Padding = new Padding(26, 22, 26, 16) };
            shell.Controls.Add(content, 1, 1);
            BuildSetupPage();
            BuildMusicPage();
            BuildAdvancedPage();

            TableLayoutPanel footer = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2, BackColor = Paper, Padding = new Padding(23, 10, 23, 8), Margin = Padding.Empty };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            footer.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            footer.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
            Panel now = new Panel { Dock = DockStyle.Fill, Margin = Padding.Empty };
            footerTitle = MakeLabel("Ready when you are", 10, FontStyle.Bold, Ink);
            footerTitle.Dock = DockStyle.Top;
            footerTitle.Height = 22;
            footerTitle.AutoEllipsis = true;
            footerStatus = MakeLabel("Set up playback to get started.", 9, FontStyle.Regular, SecondaryInk);
            footerStatus.Dock = DockStyle.Bottom;
            footerStatus.Height = 21;
            footerStatus.AutoEllipsis = true;
            now.Controls.Add(footerTitle);
            now.Controls.Add(footerStatus);
            footer.Controls.Add(now, 0, 0);
            FlowLayoutPanel transport = MakeRow();
            transport.AutoSize = true;
            transport.WrapContents = false;
            transport.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            pauseButton = MakeButton("Pause", false, 77);
            nextButton = MakeButton("Next", false, 68);
            stopButton = MakeButton("Stop", false, 68);
            pauseButton.Click += async delegate { await TransportAsync("pause"); };
            nextButton.Click += async delegate { await TransportAsync("next"); };
            stopButton.Click += async delegate { await TransportAsync("stop"); };
            transport.Controls.Add(pauseButton);
            transport.Controls.Add(nextButton);
            transport.Controls.Add(stopButton);
            footer.Controls.Add(transport, 1, 0);
            Label version = MakeLabel(Product.Version + "  ·  Keep this Windows account signed in for scheduled music.", 8.5F, FontStyle.Regular, SecondaryInk);
            version.Dock = DockStyle.Fill;
            footer.Controls.Add(version, 0, 1);
            footer.SetColumnSpan(version, 2);
            shell.Controls.Add(footer, 0, 2);
            shell.SetColumnSpan(footer, 2);
            UpdateActionState();
        }

        private void BuildSetupPage()
        {
            FlowLayoutPanel stack = NewPage("setup");
            setupStep = MakeLabel("STEP 1 OF 3  ·  PLAYBACK", 9, FontStyle.Bold, Accent);
            AddStack(stack, setupStep, 25);
            setupHeading = MakeLabel("Let's make room for music.", 23, FontStyle.Bold, Ink);
            AddStack(stack, setupHeading, 43);
            setupDescription = MakeLabel("Set up the player, paste a playlist, then choose when it plays.\r\nNo account or activation key is needed.", 10, FontStyle.Regular, SecondaryInk);
            AddStack(stack, setupDescription, 55);

            TableLayoutPanel components = new TableLayoutPanel { ColumnCount = 2, RowCount = 3, Padding = new Padding(16, 10, 16, 10), BackColor = Paper, Height = 144, Margin = new Padding(0, 8, 0, 13) };
            components.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 66));
            components.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 34));
            components.RowStyles.Add(new RowStyle(SizeType.Percent, 33.33F));
            components.RowStyles.Add(new RowStyle(SizeType.Percent, 33.33F));
            components.RowStyles.Add(new RowStyle(SizeType.Percent, 33.34F));
            AddComponentRow(components, 0, "MPV  ·  music player", out mpvState);
            AddComponentRow(components, 1, "yt-dlp  ·  YouTube playback", out ytdlpState);
            AddComponentRow(components, 2, "Deno  ·  YouTube support", out denoState);
            AddStack(stack, components, 144);
            componentSummary = MakeLabel("Checking playback components…", 10, FontStyle.Regular, SecondaryInk);
            AddStack(stack, componentSummary, 43);
            FlowLayoutPanel actions = MakeRow();
            installButton = MakeButton("Set up playback", true, 172);
            installButton.Click += async delegate { await InstallAsync(componentsReady); };
            continueButton = MakeButton("Choose my playlist  →", false, 186);
            continueButton.Click += delegate { ShowPage("music"); playlist.Focus(); };
            actions.Controls.Add(installButton);
            actions.Controls.Add(continueButton);
            AddStack(stack, actions, 44);
            installProgress = new ProgressBar { Height = 8, Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 25, Visible = false, Margin = new Padding(0, 8, 0, 8) };
            AddStack(stack, installProgress, 8);
            installDetails = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Height = 90, Visible = false, BackColor = Paper, ForeColor = SecondaryInk, Font = new Font("Segoe UI", 9F), BorderStyle = BorderStyle.FixedSingle, Margin = new Padding(0, 4, 0, 8) };
            AddStack(stack, installDetails, 90);
            Label note = MakeLabel("A one-time internet download installs these components for your Windows account.\r\nAfter setup, you can change playlists and schedules here at any time.", 9, FontStyle.Regular, SecondaryInk);
            AddStack(stack, note, 50);
        }

        private void BuildMusicPage()
        {
            FlowLayoutPanel stack = NewPage("music");
            AddStack(stack, MakeLabel("Music & schedule", 22, FontStyle.Bold, Ink), 38);
            AddStack(stack, MakeLabel("Choose a playlist for each part of your day.", 10, FontStyle.Regular, SecondaryInk), 29);
            FlowLayoutPanel sessions = MakeRow();
            morningButton = MakeButton("Morning", true, 128);
            finisherButton = MakeButton("Day Finisher", false, 139);
            morningButton.Click += delegate { SelectSession("morning"); };
            finisherButton.Click += delegate { SelectSession("finisher"); };
            sessions.Controls.Add(morningButton);
            sessions.Controls.Add(finisherButton);
            AddStack(stack, sessions, 43);

            AddStack(stack, MakeLabel("YouTube playlist", 10, FontStyle.Bold, Ink), 25);
            TableLayoutPanel playlistRow = new TableLayoutPanel { ColumnCount = 2, RowCount = 1, Height = 36, Margin = Padding.Empty };
            playlistRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            playlistRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 112));
            playlist = new TextBox { Dock = DockStyle.Fill, Margin = new Padding(0, 2, 9, 0), AccessibleName = "YouTube playlist link" };
            playlist.TextChanged += delegate { if (!loading) { playlistResult.Text = "Paste a YouTube playlist link, then check that it can be opened."; playlistResult.ForeColor = SecondaryInk; } };
            verifyButton = MakeButton("Check playlist", false, 108);
            verifyButton.Dock = DockStyle.Fill;
            verifyButton.Margin = Padding.Empty;
            verifyButton.Click += async delegate { await VerifyAsync(); };
            playlistRow.Controls.Add(playlist, 0, 0);
            playlistRow.Controls.Add(verifyButton, 1, 0);
            AddStack(stack, playlistRow, 36);
            playlistResult = MakeLabel("Paste a YouTube playlist link, then check that it can be opened.", 9, FontStyle.Regular, SecondaryInk);
            AddStack(stack, playlistResult, 30);

            AddStack(stack, MakeLabel("Speaker", 10, FontStyle.Bold, Ink), 24);
            TableLayoutPanel speakerRow = new TableLayoutPanel { ColumnCount = 3, RowCount = 1, Height = 37, Margin = Padding.Empty };
            speakerRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            speakerRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100));
            speakerRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 79));
            speaker = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill, Margin = new Padding(0, 2, 9, 0), AccessibleName = "Playback speaker", IntegralHeight = false, DropDownHeight = 220 };
            speaker.Items.Add(new AudioDeviceInfo { Id = "auto", Name = "Windows default output" });
            speaker.SelectedIndex = 0;
            speakerTestButton = MakeButton("Test sound", false, 95);
            speakerTestButton.Dock = DockStyle.Fill;
            speakerTestButton.Margin = new Padding(0, 0, 7, 0);
            speakerTestButton.Click += async delegate { await TestSpeakerAsync(); };
            refreshSpeakersButton = MakeButton("Refresh", false, 75);
            refreshSpeakersButton.Dock = DockStyle.Fill;
            refreshSpeakersButton.Margin = Padding.Empty;
            refreshSpeakersButton.Click += async delegate { await RunActionAsync("Refreshing speakers…", async delegate { await RefreshDevicesAsync(); }); };
            speakerRow.Controls.Add(speaker, 0, 0);
            speakerRow.Controls.Add(speakerTestButton, 1, 0);
            speakerRow.Controls.Add(refreshSpeakersButton, 2, 0);
            AddStack(stack, speakerRow, 37);

            TableLayoutPanel volumeRow = new TableLayoutPanel { ColumnCount = 3, RowCount = 1, Height = 37, Margin = new Padding(0, 5, 0, 5) };
            volumeRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 67));
            volumeRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            volumeRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 46));
            Label volumeCaption = MakeLabel("Volume", 9, FontStyle.Regular, SecondaryInk);
            volumeCaption.Dock = DockStyle.Fill;
            volumeCaption.TextAlign = ContentAlignment.MiddleLeft;
            volume = new TrackBar { Minimum = 0, Maximum = 100, Value = 70, TickStyle = TickStyle.None, AutoSize = false, Height = 32, Dock = DockStyle.Fill, Margin = Padding.Empty, AccessibleName = "Playback volume" };
            volumeLabel = MakeLabel("70%", 9, FontStyle.Regular, Ink);
            volumeLabel.Dock = DockStyle.Fill;
            volumeLabel.TextAlign = ContentAlignment.MiddleRight;
            volume.ValueChanged += delegate { volumeLabel.Text = volume.Value.ToString(CultureInfo.InvariantCulture) + "%"; };
            volumeRow.Controls.Add(volumeCaption, 0, 0);
            volumeRow.Controls.Add(volume, 1, 0);
            volumeRow.Controls.Add(volumeLabel, 2, 0);
            AddStack(stack, volumeRow, 37);

            scheduleEnabled = new CheckBox { Text = "Start this session automatically", AutoSize = false, Height = 28, Font = new Font(Font, FontStyle.Bold), Margin = new Padding(0, 4, 0, 1) };
            scheduleEnabled.CheckedChanged += delegate { UpdateScheduleState(); };
            AddStack(stack, scheduleEnabled, 28);
            dayRow = MakeRow();
            dayRow.WrapContents = true;
            string[] names = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
            foreach (string day in names)
            {
                CheckBox box = new CheckBox { Text = day, Tag = day, AutoSize = false, Size = new Size(63, 28), Margin = new Padding(0, 0, 4, 0), AccessibleName = day + " schedule" };
                dayChecks.Add(box);
                dayRow.Controls.Add(box);
            }
            dayRow.SizeChanged += delegate { ReflowDayChecks(); };
            AddStack(stack, dayRow, 32);

            TableLayoutPanel timing = new TableLayoutPanel { ColumnCount = 2, RowCount = 2, Height = 65, Margin = new Padding(0, 4, 0, 2) };
            timing.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 38));
            timing.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 62));
            timing.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
            timing.RowStyles.Add(new RowStyle(SizeType.Absolute, 37));
            Label starts = MakeLabel("Start time", 9, FontStyle.Bold, Ink);
            starts.Dock = DockStyle.Fill;
            Label lasts = MakeLabel("Play for", 9, FontStyle.Bold, Ink);
            lasts.Dock = DockStyle.Fill;
            timing.Controls.Add(starts, 0, 0);
            timing.Controls.Add(lasts, 1, 0);
            startTime = new DateTimePicker { Format = DateTimePickerFormat.Custom, CustomFormat = "h:mm tt", ShowUpDown = true, Width = 149, AccessibleName = "Scheduled start time", Margin = new Padding(0, 1, 0, 0) };
            timing.Controls.Add(startTime, 0, 1);
            FlowLayoutPanel duration = MakeRow();
            durationHours = MakeNumber(0, 24, 3, 0, 63);
            durationHours.AccessibleName = "Session duration hours";
            durationMinutes = MakeNumber(0, 59, 0, 0, 63);
            durationMinutes.AccessibleName = "Session duration minutes";
            duration.Controls.Add(durationHours);
            duration.Controls.Add(UnitLabel("hours", 45));
            duration.Controls.Add(durationMinutes);
            duration.Controls.Add(UnitLabel("min", 32));
            duration.Dock = DockStyle.Fill;
            duration.Margin = Padding.Empty;
            timing.Controls.Add(duration, 1, 1);
            AddStack(stack, timing, 65);
            scheduleHint = MakeLabel("Scheduling is off until you enable it and save. Closing this window keeps saved schedules active.", 8.5F, FontStyle.Regular, SecondaryInk);
            AddStack(stack, scheduleHint, 35);
            FlowLayoutPanel saveActions = MakeRow();
            saveButton = MakeButton("Save", false, 88);
            playButton = MakeButton("Save & Play", true, 135);
            saveButton.Click += async delegate { await SaveAsync(false); };
            playButton.Click += async delegate { await SaveAsync(true); };
            saveActions.Controls.Add(saveButton);
            saveActions.Controls.Add(playButton);
            AddStack(stack, saveActions, 43);
            saveMessage = MakeLabel("", 9, FontStyle.Regular, SecondaryInk);
            AddStack(stack, saveMessage, 45);
        }

        private void BuildAdvancedPage()
        {
            FlowLayoutPanel stack = NewPage("advanced");
            AddStack(stack, MakeLabel("Playback preferences", 22, FontStyle.Bold, Ink), 40);
            AddStack(stack, MakeLabel("The defaults work well for a mix of songs and long recordings.", 10, FontStyle.Regular, SecondaryInk), 35);
            samplingEnabled = new CheckBox { Text = "Sample long recordings", Height = 32, AutoSize = false, Font = new Font(Font, FontStyle.Bold), Checked = true, Margin = new Padding(0, 4, 0, 4) };
            samplingEnabled.CheckedChanged += delegate { UpdateSamplingState(); };
            AddStack(stack, samplingEnabled, 32);
            cutoff = MakeNumber(.01M, 1440, 15, 2, 92);
            sampleMin = MakeNumber(.01M, 1440, 10, 2, 92);
            sampleMax = MakeNumber(.01M, 1440, 30, 2, 92);
            fade = MakeNumber(0, 60, 5, 1, 92);
            cutoff.AccessibleName = "Long recording eligibility cutoff minutes";
            sampleMin.AccessibleName = "Minimum sample minutes";
            sampleMax.AccessibleName = "Maximum sample minutes";
            fade.AccessibleName = "Sample fade seconds";
            AddAdvancedRow(stack, "Long recording cutoff", cutoff, "minutes");
            AddAdvancedRow(stack, "Shortest sample", sampleMin, "minutes");
            AddAdvancedRow(stack, "Longest sample", sampleMax, "minutes");
            AddAdvancedRow(stack, "Fade out before the next track", fade, "seconds");
            Label history = MakeLabel("Short songs play normally. Smart starts remember heard sections,\r\nand recent-track history keeps the last 10 accepted starts.", 9, FontStyle.Regular, SecondaryInk);
            history.Margin = new Padding(0, 13, 0, 15);
            AddStack(stack, history, 48);
            wakeComputer = new CheckBox { Text = "Allow Windows to wake the computer for a session", AutoSize = false, Height = 32, Margin = new Padding(0, 3, 0, 3) };
            AddStack(stack, wakeComputer, 32);
            AddStack(stack, MakeLabel("Windows must already be signed in. A powered-off computer cannot play music.", 9, FontStyle.Regular, SecondaryInk), 38);
            saveAdvancedButton = MakeButton("Save preferences", true, 159);
            saveAdvancedButton.Click += async delegate { await SaveAsync(false); };
            FlowLayoutPanel advancedSave = MakeRow();
            advancedSave.Controls.Add(saveAdvancedButton);
            AddStack(stack, advancedSave, 48);
            AddStack(stack, MakeLabel("Maintenance", 12, FontStyle.Bold, Ink), 31);
            FlowLayoutPanel maintenance = MakeRow();
            maintenance.WrapContents = true;
            repairButton = MakeButton("Repair playback", false, 146);
            repairButton.Click += async delegate { ShowPage("setup"); await InstallAsync(true); };
            Button openLogs = MakeButton("Open log folder", false, 145);
            openLogs.Click += delegate { OpenLogFolder(); };
            uninstallButton = MakeButton("Uninstall…", false, 113);
            uninstallButton.Click += delegate { BeginUninstall(); };
            maintenance.Controls.Add(repairButton);
            maintenance.Controls.Add(openLogs);
            maintenance.Controls.Add(uninstallButton);
            AddStack(stack, maintenance, 46);
        }

        private async Task InitializeAsync()
        {
            await RunActionAsync("Checking playback…", async delegate
            {
                ComponentStatus status = await Task.Run(() => backend.GetComponentStatus());
                ApplyComponentStatus(status);
                if (status.Ready) await RefreshDevicesAsync();
                ShowPage(!setupPreview && status.Ready && HasPlaylist(settings) ? "music" : "setup");
                footerStatus.Text = status.Ready ? "Ready · choose a session and press Save & Play." : "Set up playback to continue.";
            });
            await RefreshStatusAsync();
        }

        private async Task InstallAsync(bool repair)
        {
            if (preview) { footerStatus.Text = "Interface preview — nothing is downloaded or installed."; return; }
            installDetails.Clear();
            installDetails.Visible = true;
            installProgress.Visible = true;
            await RunActionAsync(repair ? "Checking and repairing playback…" : "Downloading playback components…", async delegate
            {
                Action<string> progress = delegate(string line)
                {
                    if (IsDisposed || Disposing) return;
                    BeginInvoke(new Action(delegate
                    {
                        if (IsDisposed) return;
                        installDetails.AppendText(line + Environment.NewLine);
                        installDetails.SelectionStart = installDetails.TextLength;
                        installDetails.ScrollToCaret();
                        componentSummary.Text = line;
                    }));
                };
                await Task.Run(() => backend.InstallComponents(repair, progress));
                ComponentStatus status = await Task.Run(() => backend.GetComponentStatus());
                ApplyComponentStatus(status);
                if (!status.Ready) throw new InvalidOperationException(status.Message ?? "Playback setup did not finish. Please retry.");
                await RefreshDevicesAsync();
                footerStatus.Text = "Playback is ready. Choose your playlist and speaker next.";
                continueButton.Focus();
            });
            installProgress.Visible = false;
            if (!componentsReady) installButton.Text = "Retry setup";
        }

        private async Task RefreshDevicesAsync()
        {
            if (preview) return;
            string selectedId = GetSelectedDeviceId();
            if (selectedId == "auto" && !String.IsNullOrEmpty(settings.AudioDeviceId)) selectedId = settings.AudioDeviceId;
            List<AudioDeviceInfo> devices = await Task.Run(() => backend.GetAudioDevices());
            speaker.BeginUpdate();
            try
            {
                speaker.Items.Clear();
                foreach (AudioDeviceInfo device in devices) speaker.Items.Add(device);
                if (speaker.Items.Count == 0) speaker.Items.Add(new AudioDeviceInfo { Id = "auto", Name = "Windows default output" });
                AudioDeviceInfo selected = speaker.Items.Cast<AudioDeviceInfo>().FirstOrDefault(item => item.Id == selectedId);
                if (selected == null && selectedId != "auto")
                {
                    selected = new AudioDeviceInfo { Id = selectedId, Name = "Saved output is unavailable — choose another speaker" };
                    speaker.Items.Add(selected);
                }
                speaker.SelectedItem = selected ?? speaker.Items[0];
            }
            finally { speaker.EndUpdate(); }
        }

        private async Task VerifyAsync()
        {
            if (preview) { playlistResult.Text = "Interface preview — playlist access is not checked."; return; }
            string url = playlist.Text.Trim();
            await RunActionAsync("Checking playlist access…", async delegate
            {
                PlaylistVerification result = await Task.Run(() => backend.VerifyPlaylist(url));
                playlist.Text = result.Url;
                playlistResult.Text = String.IsNullOrEmpty(result.Title) ? result.Message : "Ready: " + result.Title;
                playlistResult.ForeColor = Accent;
                footerStatus.Text = result.Message ?? "Playlist check completed.";
            });
        }

        private async Task TestSpeakerAsync()
        {
            if (preview) { footerStatus.Text = "Interface preview — no test sound is played."; return; }
            string device = GetSelectedDeviceId();
            await RunActionAsync("Testing this speaker; the current music session will stop.", async delegate
            {
                await Task.Run(() => backend.TestSpeaker(device));
                footerStatus.Text = "Test tone finished. Confirm you heard it through the intended speaker.";
            });
        }

        private async Task SaveAsync(bool andPlay)
        {
            if (preview) { saveMessage.Text = "Interface preview — no settings or schedules are saved."; return; }
            AppSettings draft;
            try { draft = ReadSettingsFromControls(); ValidateUiValues(draft, andPlay); }
            catch (Exception exception) { ShowFailure(exception); return; }
            string sessionKey = selectedSession;
            await RunActionAsync(andPlay ? "Checking the playlist; playback will replace this app's current session." : "Saving settings and schedules…", async delegate
            {
                if (andPlay)
                {
                    PlaylistVerification verified = await Task.Run(() => backend.VerifyPlaylist(draft.GetSession(sessionKey).PlaylistUrl));
                    draft.GetSession(sessionKey).PlaylistUrl = verified.Url;
                }
                await Task.Run(() => backend.SaveSettings(draft));
                settings = draft;
                loading = true;
                playlist.Text = settings.GetSession(selectedSession).PlaylistUrl;
                loading = false;
                saveMessage.ForeColor = Accent;
                saveMessage.Text = "Saved. " + DescribeSchedules(draft);
                setupStep.Text = "STEP 3 OF 3  ·  READY";
                setupHeading.Text = "Your music is ready.";
                setupDescription.Text = "Play a session now, or leave your saved schedule to handle it.\r\nYou can change these settings whenever you need.";
                if (andPlay)
                {
                    await Task.Run(() => backend.Play(draft, sessionKey));
                    footerStatus.Text = "Starting " + SessionName(sessionKey) + "…";
                }
                else footerStatus.Text = "Settings saved. " + DescribeSchedules(draft);
            });
            await RefreshStatusAsync();
        }

        private async Task TransportAsync(string command)
        {
            if (preview) { footerStatus.Text = "Interface preview — no music player is running."; return; }
            await RunActionAsync(command == "stop" ? "Stopping music…" : "Updating playback…", async delegate
            {
                await Task.Run(delegate
                {
                    if (command == "pause") backend.Pause();
                    else if (command == "next") backend.Next();
                    else backend.Stop();
                });
                if (command == "stop")
                {
                    playing = false;
                    footerTitle.Text = "Ready when you are";
                    footerStatus.Text = "Music stopped. The next enabled schedule can still run.";
                }
            });
            await RefreshStatusAsync();
        }

        private async Task RunActionAsync(string message, Func<Task> action)
        {
            if (busy) return;
            busy = true;
            footerStatus.Text = message;
            footerStatus.ForeColor = SecondaryInk;
            UseWaitCursor = true;
            UpdateActionState();
            try { await action(); }
            catch (Exception exception) { ShowFailure(exception); }
            finally
            {
                busy = false;
                UseWaitCursor = false;
                UpdateActionState();
            }
        }

        private async Task RefreshStatusAsync()
        {
            if (preview || busy || refreshing || !componentsReady || IsDisposed) return;
            refreshing = true;
            try
            {
                PlaybackStatus state = await Task.Run(() => backend.GetStatus());
                if (IsDisposed) return;
                bool wasPlaying = playing;
                playing = state.Playing;
                footerTitle.Text = state.Playing ? (String.IsNullOrEmpty(state.Title) ? "Music is playing" : state.Title) : "Ready when you are";
                if (state.Playing) footerStatus.Text = state.Paused ? "Paused" : (state.Message ?? "Playing");
                else if (wasPlaying) footerStatus.Text = "Music stopped. The next enabled schedule can still run.";
                pauseButton.Text = state.Paused ? "Resume" : "Pause";
                UpdateActionState();
            }
            catch (Exception exception)
            {
                if (!IsDisposed) { footerStatus.Text = exception.Message; footerStatus.ForeColor = ErrorInk; }
            }
            finally { refreshing = false; }
        }

        private void ShowFailure(Exception exception)
        {
            string message = exception.GetBaseException().Message;
            if (!preview && backend != null) { try { backend.LogError(exception); } catch { } }
            footerStatus.Text = message;
            footerStatus.ForeColor = ErrorInk;
            saveMessage.Text = message;
            saveMessage.ForeColor = ErrorInk;
            if (currentPage == "setup")
            {
                componentSummary.Text = "Setup could not finish. " + message;
                componentSummary.ForeColor = ErrorInk;
                installButton.Text = "Retry setup";
            }
            MessageBox.Show(this, message, Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        private void ApplyComponentStatus(ComponentStatus state)
        {
            componentsReady = state.Ready;
            componentSummary.Text = state.Message ?? (state.Ready ? "Playback components are ready." : "An internet connection is needed for initial setup.");
            componentSummary.ForeColor = state.Ready ? Accent : SecondaryInk;
            mpvState.Text = state.Ready ? FriendlyVersion(state.MpvVersion) : "Not set up";
            ytdlpState.Text = state.Ready ? FriendlyVersion(state.YtDlpVersion) : "Not set up";
            denoState.Text = state.Ready ? FriendlyVersion(state.DenoVersion) : "Not set up";
            mpvState.ForeColor = ytdlpState.ForeColor = denoState.ForeColor = state.Ready ? Accent : SecondaryInk;
            installButton.Text = state.Ready ? "Check & repair" : "Set up playback";
            if (state.Ready)
            {
                setupStep.Text = HasPlaylist(settings) ? "STEP 3 OF 3  ·  READY" : "STEP 2 OF 3  ·  YOUR MUSIC";
                setupHeading.Text = HasPlaylist(settings) ? "Ready for your next session." : "Now make it yours.";
                setupDescription.Text = "Choose your YouTube playlist and the speaker you want to hear.\r\nSet a schedule, or play a session whenever you like.";
            }
            UpdateActionState();
        }

        private void LoadSettingsIntoControls()
        {
            loading = true;
            volume.Value = Math.Max(0, Math.Min(100, settings.Volume));
            samplingEnabled.Checked = settings.SamplingEnabled;
            SetNumber(cutoff, settings.CutoffMinutes);
            SetNumber(sampleMin, settings.SampleMinMinutes);
            SetNumber(sampleMax, settings.SampleMaxMinutes);
            SetNumber(fade, settings.FadeSeconds);
            wakeComputer.Checked = settings.WakeComputer;
            DisplaySession(settings.GetSession(selectedSession));
            loading = false;
            UpdateSamplingState();
        }

        private void StoreCurrentSession()
        {
            SessionSettings session = settings.GetSession(selectedSession);
            session.PlaylistUrl = playlist.Text.Trim();
            session.Enabled = scheduleEnabled.Checked;
            session.Days = dayChecks.Where(box => box.Checked).Select(box => (string)box.Tag).ToArray();
            session.StartTime = startTime.Value.ToString("HH:mm", CultureInfo.InvariantCulture);
            session.DurationMinutes = (int)durationHours.Value * 60 + (int)durationMinutes.Value;
        }

        private void DisplaySession(SessionSettings session)
        {
            playlist.Text = session.PlaylistUrl ?? "";
            scheduleEnabled.Checked = session.Enabled;
            foreach (CheckBox day in dayChecks) day.Checked = (session.Days ?? new string[0]).Contains((string)day.Tag);
            DateTime parsed;
            startTime.Value = DateTime.TryParseExact(session.StartTime, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out parsed) ? DateTime.Today.Add(parsed.TimeOfDay) : DateTime.Today.AddHours(6).AddMinutes(45);
            int duration = Math.Max(1, Math.Min(1440, session.DurationMinutes));
            durationHours.Value = duration / 60;
            durationMinutes.Value = duration % 60;
            playlistResult.Text = "Paste a YouTube playlist link, then check that it can be opened.";
            playlistResult.ForeColor = SecondaryInk;
            UpdateScheduleState();
        }

        private void SelectSession(string key)
        {
            if (busy || key == selectedSession) return;
            StoreCurrentSession();
            selectedSession = key;
            loading = true;
            DisplaySession(settings.GetSession(key));
            loading = false;
            StyleButton(morningButton, key == "morning");
            StyleButton(finisherButton, key == "finisher");
            saveMessage.Text = "";
        }

        private AppSettings ReadSettingsFromControls()
        {
            StoreCurrentSession();
            return new AppSettings
            {
                Schema = settings.Schema,
                AudioDeviceId = GetSelectedDeviceId(),
                Volume = volume.Value,
                SamplingEnabled = samplingEnabled.Checked,
                CutoffMinutes = (double)cutoff.Value,
                SampleMinMinutes = (double)sampleMin.Value,
                SampleMaxMinutes = (double)sampleMax.Value,
                FadeSeconds = (double)fade.Value,
                WakeComputer = wakeComputer.Checked,
                Morning = CloneSession(settings.Morning),
                Finisher = CloneSession(settings.Finisher)
            };
        }

        private void ValidateUiValues(AppSettings draft, bool andPlay)
        {
            if (draft.SampleMinMinutes > draft.SampleMaxMinutes) throw new ArgumentException("The shortest sample cannot be longer than the longest sample. Check Advanced playback preferences.");
            foreach (string key in new string[] { "morning", "finisher" })
            {
                SessionSettings session = draft.GetSession(key);
                if (session.DurationMinutes < 1 || session.DurationMinutes > 1440) throw new ArgumentException(SessionName(key) + " must run for between 1 minute and 24 hours.");
                if (session.Enabled && String.IsNullOrWhiteSpace(session.PlaylistUrl)) throw new ArgumentException("Paste a playlist for " + SessionName(key) + " before enabling its schedule.");
                if (session.Enabled && session.Days.Length == 0) throw new ArgumentException("Choose at least one day for " + SessionName(key) + ".");
            }
            if (andPlay && String.IsNullOrWhiteSpace(draft.GetSession(selectedSession).PlaylistUrl)) throw new ArgumentException("Paste a YouTube playlist link before playing this session.");
        }

        private void UpdateScheduleState()
        {
            if (dayRow == null || startTime == null) return;
            dayRow.Enabled = scheduleEnabled.Checked && !busy;
            startTime.Enabled = scheduleEnabled.Checked && !busy;
            if (scheduleHint != null) scheduleHint.Text = scheduleEnabled.Checked
                ? "Click Save to apply this schedule. Closing this window keeps saved schedules active."
                : "Scheduling is off. Save & Play starts this session now.";
        }

        private void UpdateSamplingState()
        {
            if (sampleMin == null) return;
            sampleMin.Enabled = sampleMax.Enabled = fade.Enabled = samplingEnabled.Checked && !busy;
        }

        private void UpdateActionState()
        {
            if (installButton == null || playButton == null) return;
            installButton.Enabled = !busy;
            continueButton.Enabled = !busy && componentsReady;
            saveButton.Enabled = playButton.Enabled = saveAdvancedButton.Enabled = !busy && componentsReady;
            verifyButton.Enabled = speakerTestButton.Enabled = refreshSpeakersButton.Enabled = !busy && componentsReady;
            repairButton.Enabled = !busy;
            uninstallButton.Enabled = !busy && !preview && File.Exists(Path.Combine(paths.InstallRoot, "unins000.exe"));
            pauseButton.Enabled = nextButton.Enabled = !busy && playing;
            // A loading or damaged player may have no media title yet. Stop is
            // scoped to this app and must remain available for recovery.
            stopButton.Enabled = !busy;
            morningButton.Enabled = finisherButton.Enabled = !busy;
            playlist.Enabled = speaker.Enabled = volume.Enabled = scheduleEnabled.Enabled = !busy;
            durationHours.Enabled = durationMinutes.Enabled = !busy;
            samplingEnabled.Enabled = cutoff.Enabled = wakeComputer.Enabled = !busy;
            UpdateScheduleState();
            UpdateSamplingState();
        }

        private void ShowPage(string key)
        {
            currentPage = key;
            foreach (KeyValuePair<string, Panel> page in pages) page.Value.Visible = page.Key == key;
            foreach (KeyValuePair<string, Button> item in navigation)
            {
                item.Value.BackColor = item.Key == key ? AccentSoft : Color.Transparent;
                item.Value.ForeColor = item.Key == key ? Accent : Ink;
                item.Value.Font = new Font(Font, item.Key == key ? FontStyle.Bold : FontStyle.Regular);
            }
            pages[key].BringToFront();
        }

        private void OpenLogFolder()
        {
            if (preview) { footerStatus.Text = "Interface preview — no log folder is opened."; return; }
            try
            {
                Directory.CreateDirectory(paths.DataRoot);
                Process.Start(new ProcessStartInfo("explorer.exe", "\"" + paths.DataRoot + "\"") { UseShellExecute = false });
            }
            catch (Exception exception) { ShowFailure(exception); }
        }

        private void BeginUninstall()
        {
            if (preview || busy) return;
            string uninstaller = Path.Combine(paths.InstallRoot, "unins000.exe");
            if (!File.Exists(uninstaller)) { MessageBox.Show(this, "Use Windows Settings → Apps to remove Automatic Music.", Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            DialogResult choice = MessageBox.Show(this, "Open the uninstaller? The app and its schedules will be removed. Your saved settings and listening history are kept.", "Uninstall Automatic Music", MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
            if (choice != DialogResult.OK) return;
            try
            {
                Process.Start(new ProcessStartInfo(uninstaller) { UseShellExecute = true });
                allowExit = true;
                Close();
            }
            catch (Exception exception) { ShowFailure(exception); }
        }

        private void HandleFormClosing(object sender, FormClosingEventArgs e)
        {
            if (busy && !allowExit && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                MessageBox.Show(this, "Please wait for the current operation to finish. Closing it now could interrupt playback setup.", Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private FlowLayoutPanel NewPage(string name)
        {
            Panel panel = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Canvas, Visible = false };
            FlowLayoutPanel stack = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = Padding.Empty, Margin = Padding.Empty, BackColor = Canvas };
            panel.Controls.Add(stack);
            content.Controls.Add(panel);
            pages.Add(name, panel);
            panel.Resize += delegate { SizeStack(stack, panel.ClientSize.Width - SystemInformation.VerticalScrollBarWidth); };
            stack.ControlAdded += delegate { SizeStack(stack, Math.Max(300, panel.ClientSize.Width - SystemInformation.VerticalScrollBarWidth)); };
            return stack;
        }

        private static void SizeStack(FlowLayoutPanel stack, int width)
        {
            width = Math.Max(300, width);
            stack.Width = width;
            foreach (Control control in stack.Controls) control.Width = width - control.Margin.Horizontal;
        }

        private static void AddStack(FlowLayoutPanel stack, Control control, int height)
        {
            control.Height = height;
            control.Width = Math.Max(300, stack.Width);
            if (control.Margin == new Padding(3)) control.Margin = Padding.Empty;
            stack.Controls.Add(control);
        }

        private Button NavigationButton(string text, string page)
        {
            Button button = new Button { Text = text, UseMnemonic = false, Width = 145, Height = 43, TextAlign = ContentAlignment.MiddleLeft, FlatStyle = FlatStyle.Flat, BackColor = Color.Transparent, ForeColor = Ink, Margin = new Padding(0, 0, 0, 7), Padding = new Padding(10, 0, 0, 0), UseVisualStyleBackColor = false };
            button.FlatAppearance.BorderSize = 0;
            button.FlatAppearance.MouseOverBackColor = AccentSoft;
            button.Click += delegate { ShowPage(page); };
            navigation.Add(page, button);
            return button;
        }

        private static Label MakeLabel(string text, float size, FontStyle style, Color color)
        {
            return new Label { Text = text, Font = new Font("Segoe UI", size, style, GraphicsUnit.Point), ForeColor = color, AutoSize = false, Margin = Padding.Empty, BackColor = Color.Transparent, UseMnemonic = false };
        }

        private static FlowLayoutPanel MakeRow()
        {
            return new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, WrapContents = false, AutoSize = false, Margin = Padding.Empty, Padding = Padding.Empty };
        }

        private static Label UnitLabel(string text, int width)
        {
            Label label = MakeLabel(text, 9, FontStyle.Regular, SecondaryInk);
            label.Width = width;
            label.Height = 30;
            label.TextAlign = ContentAlignment.MiddleLeft;
            label.Margin = new Padding(5, 0, 7, 0);
            return label;
        }

        private static Button MakeButton(string text, bool primary, int width)
        {
            Button button = new Button { Text = text, UseMnemonic = false, Height = 35, Width = width, FlatStyle = FlatStyle.Flat, Margin = new Padding(0, 0, 8, 0), Font = new Font("Segoe UI", 9F, FontStyle.Bold), UseVisualStyleBackColor = false };
            StyleButton(button, primary);
            return button;
        }

        private static void StyleButton(Button button, bool primary)
        {
            button.BackColor = primary ? Accent : Paper;
            button.ForeColor = primary ? Color.White : Ink;
            button.FlatAppearance.BorderSize = 1;
            button.FlatAppearance.BorderColor = primary ? Accent : Line;
            button.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(22, 88, 111) : AccentSoft;
            button.FlatAppearance.MouseDownBackColor = primary ? Color.FromArgb(19, 77, 97) : Color.FromArgb(210, 228, 232);
        }

        private static NumericUpDown MakeNumber(decimal min, decimal max, decimal value, int decimals, int width)
        {
            return new NumericUpDown { Minimum = min, Maximum = max, Value = value, DecimalPlaces = decimals, Width = width, Height = 30, ThousandsSeparator = false, Margin = new Padding(0, 1, 0, 0), BackColor = Paper, ForeColor = Ink };
        }

        private static void SetNumber(NumericUpDown input, double value)
        {
            if (Double.IsNaN(value) || Double.IsInfinity(value)) return;
            input.Value = Math.Max(input.Minimum, Math.Min(input.Maximum, (decimal)value));
        }

        private static void AddComponentRow(TableLayoutPanel parent, int row, string text, out Label state)
        {
            Label name = MakeLabel(text, 10, FontStyle.Regular, Ink);
            name.Dock = DockStyle.Fill;
            name.TextAlign = ContentAlignment.MiddleLeft;
            state = MakeLabel("Checking…", 9, FontStyle.Regular, SecondaryInk);
            state.Dock = DockStyle.Fill;
            state.TextAlign = ContentAlignment.MiddleRight;
            state.AutoEllipsis = true;
            parent.Controls.Add(name, 0, row);
            parent.Controls.Add(state, 1, row);
        }

        private static void AddAdvancedRow(FlowLayoutPanel stack, string caption, NumericUpDown input, string unit)
        {
            TableLayoutPanel row = new TableLayoutPanel { ColumnCount = 3, RowCount = 1, Height = 44, Margin = Padding.Empty };
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 101));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 69));
            Label label = MakeLabel(caption, 10, FontStyle.Regular, Ink);
            label.Dock = DockStyle.Fill;
            label.TextAlign = ContentAlignment.MiddleLeft;
            input.Anchor = AnchorStyles.Left;
            Label unitLabel = UnitLabel(unit, 67);
            unitLabel.Dock = DockStyle.Fill;
            row.Controls.Add(label, 0, 0);
            row.Controls.Add(input, 1, 0);
            row.Controls.Add(unitLabel, 2, 0);
            AddStack(stack, row, 44);
        }

        private string GetSelectedDeviceId()
        {
            AudioDeviceInfo selected = speaker.SelectedItem as AudioDeviceInfo;
            return selected == null ? "auto" : selected.Id;
        }

        private static SessionSettings CloneSession(SessionSettings session)
        {
            return new SessionSettings { Enabled = session.Enabled, PlaylistUrl = session.PlaylistUrl, StartTime = session.StartTime, Days = (string[])session.Days.Clone(), DurationMinutes = session.DurationMinutes };
        }

        private static string SessionName(string key) { return key == "morning" ? "Morning" : "Day Finisher"; }
        private static bool HasPlaylist(AppSettings value) { return !String.IsNullOrWhiteSpace(value.Morning.PlaylistUrl) || !String.IsNullOrWhiteSpace(value.Finisher.PlaylistUrl); }
        private static string FriendlyVersion(string value) { return String.IsNullOrWhiteSpace(value) ? "Ready" : value.Split(new char[] { '\r', '\n' })[0]; }
        private static string DescribeSchedules(AppSettings value)
        {
            if (value.Morning.Enabled && value.Finisher.Enabled) return "Morning and Day Finisher schedules are on.";
            if (value.Morning.Enabled) return "Morning schedule is on.";
            if (value.Finisher.Enabled) return "Day Finisher schedule is on.";
            return "Automatic scheduling is off.";
        }

        private void ReflowDayChecks()
        {
            if (dayChecks.Count == 0 || dayRow.ClientSize.Width <= 0) return;
            int rows = 1;
            int used = 0;
            int rowHeight = 0;
            foreach (CheckBox check in dayChecks)
            {
                int width = check.Width + check.Margin.Horizontal;
                rowHeight = Math.Max(rowHeight, check.Height + check.Margin.Vertical);
                if (used > 0 && used + width > dayRow.ClientSize.Width) { rows++; used = 0; }
                used += width;
            }
            int target = rows * rowHeight + 4;
            if (dayRow.Height != target) dayRow.Height = target;
        }

        public void CaptureScreenshot(string destination, string pageName = null)
        {
            if (!preview) throw new InvalidOperationException("Screenshot capture is only available in fixture mode.");
            Show();
            Application.DoEvents();
            if (!String.IsNullOrEmpty(pageName)) ShowPage(pageName);
            PerformLayout();
            foreach (Panel page in pages.Values) page.PerformLayout();
            Application.DoEvents();
            using (Bitmap bitmap = new Bitmap(Width, Height))
            {
                DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
                bitmap.Save(destination, System.Drawing.Imaging.ImageFormat.Png);
            }
            allowExit = true;
            Close();
        }

        public void RunUiSelfTest()
        {
            if (!preview) throw new InvalidOperationException("UI tests require fixture mode.");
            Show();
            Application.DoEvents();
            if (settings.Morning.Enabled) throw new InvalidOperationException("New schedules must default to disabled.");
            playlist.Text = "https://www.youtube.com/playlist?list=PLmorningFixture";
            durationHours.Value = 1;
            durationMinutes.Value = 30;
            SelectSession("finisher");
            playlist.Text = "https://www.youtube.com/playlist?list=PLfinisherFixture";
            SelectSession("morning");
            if (!playlist.Text.Contains("PLmorningFixture") || durationHours.Value != 1 || durationMinutes.Value != 30) throw new InvalidOperationException("Session switching lost edits.");
            AppSettings draft = ReadSettingsFromControls();
            if (draft.Morning.DurationMinutes != 90 || !draft.Finisher.PlaylistUrl.Contains("PLfinisherFixture")) throw new InvalidOperationException("Settings mapping failed.");
            ValidateUiValues(draft, true);
            draft.Morning.DurationMinutes = 0;
            bool rejected = false;
            try { ValidateUiValues(draft, true); } catch (ArgumentException) { rejected = true; }
            if (!rejected) throw new InvalidOperationException("Invalid session duration was accepted.");
            draft.Morning.DurationMinutes = 90;
            draft.SampleMinMinutes = 31;
            draft.SampleMaxMinutes = 30;
            rejected = false;
            try { ValidateUiValues(draft, true); } catch (ArgumentException) { rejected = true; }
            if (!rejected) throw new InvalidOperationException("Invalid sample bounds were accepted.");
            if (cutoff.Value != 15 || sampleMin.Value != 10 || sampleMax.Value != 30 || fade.Value != 5) throw new InvalidOperationException("Playback defaults changed.");
            allowExit = true;
            Close();
        }
    }
}
