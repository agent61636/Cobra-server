using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using Unbroken.LaunchBox.Plugins;
using Unbroken.LaunchBox.Plugins.Data;

namespace CobraHiscore
{
    /// <summary>
    /// LaunchBox and Big Box call this around every game. When an emulator game exits,
    /// the plugin sends its new hiscore file and details to scores.songofeo.com.
    /// Nothing here blocks LaunchBox: the work runs in the background and never throws.
    /// </summary>
    public sealed class HiscorePlugin : IGameLaunchingPlugin
    {
        static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        static readonly object Gate = new object();

        readonly string folder;
        GameInfo current;
        DateTime launchedUtc;

        public HiscorePlugin()
        {
            folder = Path.GetDirectoryName(typeof(HiscorePlugin).Assembly.Location) ?? ".";
        }

        public void OnBeforeGameLaunching(IGame game, IAdditionalApplication app, IEmulator emulator)
        {
            try
            {
                lock (Gate)
                {
                    // Hiscore files only come from emulators; skip Steam and other PC games.
                    if (game == null || emulator == null) { current = null; return; }
                    var rom = !string.IsNullOrWhiteSpace(app?.ApplicationPath) ? app.ApplicationPath : game.ApplicationPath;
                    current = new GameInfo
                    {
                        Title = game.Title,
                        Platform = game.Platform,
                        RomName = string.IsNullOrWhiteSpace(rom) ? "" : Path.GetFileNameWithoutExtension(rom),
                    };
                    launchedUtc = DateTime.UtcNow;
                }
            }
            catch (Exception e) { Log("launch: " + e.Message); }
        }

        public void OnAfterGameLaunched(IGame game, IAdditionalApplication app, IEmulator emulator) { }

        public void OnGameExited()
        {
            GameInfo game;
            DateTime since;
            lock (Gate)
            {
                game = current;
                since = launchedUtc;
                current = null;
            }
            if (game == null) return;
            Task.Run(async () =>
            {
                try
                {
                    var settings = Settings.Load(folder);
                    var sync = new HiscoreSync(settings, () => ApiKey.Load(settings.KeyPath), Http, Log, folder);
                    await sync.SyncAsync(game, since).ConfigureAwait(false);
                }
                catch (Exception e) { Log("exit: " + e.Message); }
            });
        }

        void Log(string message)
        {
            try
            {
                var path = Path.Combine(folder, "plugin.log");
                lock (Gate)
                {
                    if (File.Exists(path) && new FileInfo(path).Length > 1024 * 1024)
                        File.Move(path, path + ".1", true);
                    File.AppendAllText(path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {message}{Environment.NewLine}");
                }
            }
            catch { }
        }
    }
}
