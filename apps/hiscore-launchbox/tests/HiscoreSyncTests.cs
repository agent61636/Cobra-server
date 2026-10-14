using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace CobraHiscore.Tests
{
    /// <summary>Stands in for scores.songofeo.com and records every request.</summary>
    sealed class FakeServer : HttpMessageHandler
    {
        public readonly List<(string Method, string Path, string Auth, byte[] Body)> Requests = new();
        public Func<HttpRequestMessage, HttpStatusCode> Answer = _ => HttpStatusCode.Created;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            var body = request.Content == null ? Array.Empty<byte>() : await request.Content.ReadAsByteArrayAsync(cancel);
            Requests.Add((request.Method.Method, request.RequestUri.AbsolutePath, request.Headers.Authorization?.ToString(), body));
            return new HttpResponseMessage(Answer(request));
        }
    }

    public sealed class HiscoreSyncTests : IDisposable
    {
        readonly string root = Path.Combine(Path.GetTempPath(), "cobra-hiscore-tests-" + Guid.NewGuid().ToString("N"));
        readonly List<string> log = new();
        readonly FakeServer server = new();

        public HiscoreSyncTests() => Directory.CreateDirectory(root);
        public void Dispose() { try { Directory.Delete(root, true); } catch { } }

        string WriteHi(string relative, string content, double secondsAgo = 30)
        {
            var path = Path.Combine(root, "saves", relative);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, content);
            File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(-secondsAgo));
            return path;
        }

        HiscoreSync Make(Settings s = null)
        {
            s ??= new Settings
            {
                Server = "https://scores.example",
                SettleSeconds = 0,
                Folders = new List<WatchFolder> { new WatchFolder { Path = Path.Combine(root, "saves"), System = "auto" } },
            };
            return new HiscoreSync(s, () => "the-key", new HttpClient(server), log.Add, root);
        }

        static readonly GameInfo Galaga = new GameInfo { Title = "Galaga", Platform = "Arcade", RomName = "galaga" };

        [Fact]
        public void Segments_match_the_agent_and_server_rules()
        {
            Assert.Equal("galaga.hi", HiscoreSync.Segment("galaga.hi"));
            Assert.Equal("Street_Fighter_II", HiscoreSync.Segment("Street Fighter II"));
            Assert.Equal("unknown", HiscoreSync.Segment("..."));
            Assert.Equal(64, HiscoreSync.Segment(new string('a', 100)).Length);
        }

        [Fact]
        public void System_is_the_core_folder_unless_named()
        {
            var auto = new WatchFolder { Path = Path.Combine(root, "saves"), System = "auto" };
            Assert.Equal("fbneo", HiscoreSync.SystemName(auto, Path.Combine(root, "saves", "fbneo", "hi", "galaga.hi")));
            Assert.Equal("retroarch", HiscoreSync.SystemName(auto, Path.Combine(root, "saves", "galaga.hi")));
            var named = new WatchFolder { Path = Path.Combine(root, "mame"), System = "mame" };
            Assert.Equal("mame", HiscoreSync.SystemName(named, Path.Combine(root, "mame", "hi", "galaga.hi")));
        }

        [Fact]
        public void Finds_only_files_written_since_launch()
        {
            WriteHi("fbneo/hi/galaga.hi", "new", secondsAgo: 5);
            WriteHi("fbneo/hi/dkong.hi", "old", secondsAgo: 3600);
            File.WriteAllText(Path.Combine(root, "saves", "fbneo", "hi", "notes.txt"), "x");
            var found = Make().FindChanged(DateTime.UtcNow.AddMinutes(-1));
            var one = Assert.Single(found);
            Assert.Equal(("fbneo", "galaga.hi"), (one.System, one.Name));
        }

        [Fact]
        public async Task Uploads_the_file_then_the_title()
        {
            WriteHi("fbneo/hi/galaga.hi", "SCORES");
            await Make().SyncAsync(Galaga, DateTime.UtcNow.AddMinutes(-5));

            Assert.Equal(2, server.Requests.Count);
            var file = server.Requests[0];
            Assert.Equal(("PUT", "/upload/fbneo/galaga.hi", "Bearer the-key"), (file.Method, file.Path, file.Auth));
            Assert.Equal("SCORES", System.Text.Encoding.UTF8.GetString(file.Body));
            var meta = server.Requests[1];
            Assert.Equal("/upload/fbneo/galaga.hi/meta", meta.Path);
            var json = JsonDocument.Parse(meta.Body).RootElement;
            Assert.Equal("Galaga", json.GetProperty("title").GetString());
            Assert.Equal("Arcade", json.GetProperty("platform").GetString());
            Assert.False(json.TryGetProperty("hi2txt", out _));
        }

        [Fact]
        public async Task Title_goes_only_to_the_game_that_was_played()
        {
            WriteHi("fbneo/hi/galaga.hi", "a");
            WriteHi("fbneo/hi/galagao.hi", "b");    // another file the session touched
            await Make().SyncAsync(Galaga, DateTime.UtcNow.AddMinutes(-5));
            Assert.Equal(new[] { "/upload/fbneo/galaga.hi", "/upload/fbneo/galaga.hi/meta", "/upload/fbneo/galagao.hi" },
                         server.Requests.Select(r => r.Path).OrderBy(p => p, StringComparer.Ordinal).ToArray());
        }

        [Fact]
        public async Task Nothing_written_means_nothing_sent()
        {
            WriteHi("fbneo/hi/galaga.hi", "old", secondsAgo: 3600);
            await Make().SyncAsync(Galaga, DateTime.UtcNow.AddMinutes(-5));
            Assert.Empty(server.Requests);
            Assert.Contains(log, l => l.Contains("no new .hi file"));
        }

        [Fact]
        public async Task Details_that_fail_are_kept_and_sent_later()
        {
            WriteHi("fbneo/hi/galaga.hi", "a");
            server.Answer = r => r.RequestUri.AbsolutePath.EndsWith("/meta") ? HttpStatusCode.BadGateway : HttpStatusCode.Created;
            var sync = Make();
            await sync.SyncAsync(Galaga, DateTime.UtcNow.AddMinutes(-5));
            Assert.True(File.Exists(Path.Combine(root, "pending.json")));

            server.Requests.Clear();
            server.Answer = _ => HttpStatusCode.OK;
            await sync.SendPendingAsync(CancellationToken.None);
            var sent = Assert.Single(server.Requests);
            Assert.Equal("/upload/fbneo/galaga.hi/meta", sent.Path);
            Assert.False(File.Exists(Path.Combine(root, "pending.json")));
        }

        [Fact]
        public void Hi2txt_arguments_use_the_systems_hiscore_dat()
        {
            var s = new Settings { HiscoreDat = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["fbneo"] = @"C:\ra\system\fbneo\hiscore.dat" } };
            var sync = Make(s);
            var file = new ChangedFile { FullPath = Path.Combine(root, "galaga.hi"), System = "FBNeo", Name = "galaga.hi" };
            Assert.Equal(new[] { "-hiscoredat", @"C:\ra\system\fbneo\hiscore.dat", "-r", file.FullPath }, sync.Hi2txtArgs(file).ToArray());
            file.System = "mame";
            Assert.Equal(new[] { "-r", file.FullPath }, sync.Hi2txtArgs(file).ToArray());
            s.Hi2txtArgs = new List<string> { "-ra", "{game}", "{system}" };
            Assert.Equal(new[] { "-ra", "galaga", "mame" }, sync.Hi2txtArgs(file).ToArray());
        }

        [Fact]
        public void Settings_take_server_and_folders_from_the_agent()
        {
            var agent = Path.Combine(root, "agent");
            Directory.CreateDirectory(agent);
            File.WriteAllText(Path.Combine(agent, "config.json"),
                "{ \"server\": \"https://scores.songofeo.com\", \"intervalSeconds\": 15, \"folders\": [ { \"path\": \"C:\\\\RetroArch-Win64\\\\saves\", \"system\": \"auto\" } ] }");
            File.WriteAllText(Path.Combine(root, "config.json"),
                "{ // the plugin's own\n \"agentFolder\": " + JsonSerializer.Serialize(agent) + ", \"hi2txt\": \"C:\\\\hi2txt\\\\hi2txt.exe\", \"hiscoreDat\": { \"fbneo\": \"x.dat\" }, }");
            var s = Settings.Load(root);
            Assert.Equal("https://scores.songofeo.com", s.Server);
            Assert.Equal(@"C:\RetroArch-Win64\saves", Assert.Single(s.Folders).Path);
            Assert.Equal("x.dat", s.HiscoreDat["FBNEO"]);
            Assert.Equal(Path.Combine(agent, "key.dat"), s.KeyPath);
        }

        [Fact]
        public void Key_dat_from_PowerShell_can_be_read()
        {
            if (!OperatingSystem.IsWindows()) return;   // DPAPI is Windows only
            var hex = ApiKey.EncryptForTests("s3cret-key_123");
            Assert.StartsWith("01000000d08c9ddf", hex);    // the DPAPI blob header PowerShell writes too
            Assert.Equal("s3cret-key_123", ApiKey.Decrypt(hex));
        }
    }
}
