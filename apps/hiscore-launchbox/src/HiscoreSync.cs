using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace CobraHiscore
{
    /// <summary>What LaunchBox told us about the game that just ran.</summary>
    internal sealed class GameInfo
    {
        public string Title { get; set; }
        public string Platform { get; set; }
        /// <summary>The ROM file's name without its extension, e.g. "galaga". Matches the .hi file name.</summary>
        public string RomName { get; set; }
    }

    /// <summary>A .hi file that changed while the game ran, with the system name the agent would give it.</summary>
    internal sealed class ChangedFile
    {
        public string FullPath { get; set; }
        public string System { get; set; }
        public string Name { get; set; }
        public DateTime WrittenUtc { get; set; }
    }

    /// <summary>
    /// After a game exits: finds the .hi files it wrote, uploads them straight away
    /// (the agent would get to them within 15 s anyway), then tells the server the
    /// game's proper title and platform and, when hi2txt is set up, the readable
    /// score table. Uploads of the same bytes are ignored by the server, so the
    /// plugin and the agent never fight. Details that fail to send are kept in
    /// pending.json and sent after the next game.
    /// </summary>
    internal sealed class HiscoreSync
    {
        readonly Settings settings;
        readonly Func<string> apiKey;
        readonly HttpClient http;
        readonly Action<string> log;
        readonly string pendingPath;
        static readonly Regex NotSegment = new Regex("[^A-Za-z0-9._-]");
        static readonly SemaphoreSlim OneAtATime = new SemaphoreSlim(1, 1);

        public HiscoreSync(Settings settings, Func<string> apiKey, HttpClient http, Action<string> log, string stateFolder)
        {
            this.settings = settings;
            this.apiKey = apiKey;
            this.http = http;
            this.log = log;
            pendingPath = Path.Combine(stateFolder, "pending.json");
        }

        /// <summary>Same rule as the agent and the server: letters, digits, '.', '_' or '-', max 64.</summary>
        public static string Segment(string s)
        {
            var clean = NotSegment.Replace(s ?? "", "_").Trim('.', '_', '-');
            if (clean.Length > 64) clean = clean.Substring(0, 64);
            return clean.Length == 0 ? "unknown" : clean;
        }

        /// <summary>A folder can name its system; "auto" uses the first subfolder (RetroArch's core folder).</summary>
        public static string SystemName(WatchFolder folder, string filePath)
        {
            if (!string.IsNullOrWhiteSpace(folder.System) && !folder.System.Equals("auto", StringComparison.OrdinalIgnoreCase))
                return Segment(folder.System);
            var root = Path.GetFullPath(folder.Path).TrimEnd('\\', '/');
            var dir = Path.GetDirectoryName(Path.GetFullPath(filePath)) ?? "";
            var rel = dir.Length > root.Length ? dir.Substring(root.Length).TrimStart('\\', '/') : "";
            var first = rel.Split('\\', '/').FirstOrDefault(p => p.Length > 0);
            return first == null ? "retroarch" : Segment(first);
        }

        public List<ChangedFile> FindChanged(DateTime sinceUtc)
        {
            var found = new List<ChangedFile>();
            foreach (var folder in settings.Folders)
            {
                if (string.IsNullOrWhiteSpace(folder?.Path) || !Directory.Exists(folder.Path)) continue;
                IEnumerable<string> files;
                try { files = Directory.EnumerateFiles(folder.Path, "*.hi", SearchOption.AllDirectories).ToList(); }
                catch (Exception e) { log($"can't read {folder.Path}: {e.Message}"); continue; }
                foreach (var f in files)
                {
                    DateTime written;
                    try { written = File.GetLastWriteTimeUtc(f); } catch { continue; }
                    if (written < sinceUtc) continue;
                    found.Add(new ChangedFile
                    {
                        FullPath = f, System = SystemName(folder, f), Name = Segment(Path.GetFileName(f)), WrittenUtc = written,
                    });
                }
            }
            return found;
        }

        /// <summary>Called on a background thread once the game has exited.</summary>
        public async Task SyncAsync(GameInfo game, DateTime launchedUtc, CancellationToken cancel = default)
        {
            await OneAtATime.WaitAsync(cancel).ConfigureAwait(false);
            try
            {
                if (string.IsNullOrWhiteSpace(settings.Server)) { log("no server set; check the agent's config.json"); return; }
                await SendPendingAsync(cancel).ConfigureAwait(false);

                // Give the emulator a moment to finish writing, then wait for files still being written.
                await Task.Delay(TimeSpan.FromSeconds(settings.SettleSeconds), cancel).ConfigureAwait(false);
                var changed = FindChanged(launchedUtc.AddSeconds(-2));
                for (var i = 0; i < 10 && changed.Any(c => DateTime.UtcNow - c.WrittenUtc < TimeSpan.FromSeconds(2)); i++)
                {
                    await Task.Delay(1000, cancel).ConfigureAwait(false);
                    changed = FindChanged(launchedUtc.AddSeconds(-2));
                }
                if (changed.Count == 0) { log($"{game.Title}: no new .hi file"); return; }

                foreach (var file in changed)
                {
                    var stem = Path.GetFileNameWithoutExtension(file.FullPath);
                    var isThisGame = changed.Count == 1 ||
                        string.Equals(stem, game.RomName, StringComparison.OrdinalIgnoreCase);
                    try
                    {
                        var code = await UploadFileAsync(file, cancel).ConfigureAwait(false);
                        log($"uploaded {file.System}/{file.Name} ({code})");
                    }
                    catch (Exception e)
                    {
                        // The agent retries the file itself; keep the details for later.
                        log($"upload of {file.System}/{file.Name} failed, the agent will retry: {e.Message}");
                    }
                    var meta = new Dictionary<string, object>();
                    if (isThisGame)
                    {
                        if (!string.IsNullOrWhiteSpace(game.Title)) meta["title"] = game.Title.Trim();
                        if (!string.IsNullOrWhiteSpace(game.Platform)) meta["platform"] = game.Platform.Trim();
                    }
                    var table = RunHi2txt(file);
                    if (table != null) meta["hi2txt"] = table;
                    if (meta.Count > 0) await SendMetaOrKeepAsync(file.System, file.Name, meta, cancel).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception e) { log("sync failed: " + e.Message); }
            finally { OneAtATime.Release(); }
        }

        async Task<int> UploadFileAsync(ChangedFile file, CancellationToken cancel)
        {
            var bytes = File.ReadAllBytes(file.FullPath);
            var url = $"{settings.Server.TrimEnd('/')}/upload/{Uri.EscapeDataString(file.System)}/{Uri.EscapeDataString(file.Name)}";
            using var req = new HttpRequestMessage(HttpMethod.Put, url) { Content = new ByteArrayContent(bytes) };
            req.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey());
            req.Headers.TryAddWithoutValidation("X-File-Mtime", file.WrittenUtc.ToString("yyyy-MM-ddTHH:mm:ssZ"));
            req.Headers.TryAddWithoutValidation("X-Source", Segment(Environment.MachineName));
            using var resp = await http.SendAsync(req, cancel).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode) throw new HttpRequestException($"server answered {(int)resp.StatusCode}");
            return (int)resp.StatusCode;
        }

        async Task SendMetaOrKeepAsync(string system, string name, Dictionary<string, object> meta, CancellationToken cancel)
        {
            var json = JsonSerializer.Serialize(meta);
            try
            {
                var code = await SendMetaAsync(system, name, json, cancel).ConfigureAwait(false);
                if (code == 404) { Keep(system, name, json); log($"{system}/{name}: server hasn't got the file yet; details kept for later"); }
                else log($"sent details for {system}/{name} ({code})");
            }
            catch (Exception e)
            {
                Keep(system, name, json);
                log($"details for {system}/{name} kept for later: {e.Message}");
            }
        }

        async Task<int> SendMetaAsync(string system, string name, string json, CancellationToken cancel)
        {
            var url = $"{settings.Server.TrimEnd('/')}/upload/{Uri.EscapeDataString(system)}/{Uri.EscapeDataString(name)}/meta";
            using var req = new HttpRequestMessage(HttpMethod.Put, url) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey());
            using var resp = await http.SendAsync(req, cancel).ConfigureAwait(false);
            var code = (int)resp.StatusCode;
            if (code == 404 || resp.IsSuccessStatusCode) return code;
            if (code == 400) { log($"server refused details for {system}/{name}; dropped"); return code; }
            throw new HttpRequestException($"server answered {code}");
        }

        // ---- details waiting to be sent -------------------------------------------------------

        sealed class Pending
        {
            public string System { get; set; }
            public string Name { get; set; }
            public string Json { get; set; }
        }

        List<Pending> ReadPending()
        {
            try
            {
                return File.Exists(pendingPath)
                    ? JsonSerializer.Deserialize<List<Pending>>(File.ReadAllText(pendingPath)) ?? new List<Pending>()
                    : new List<Pending>();
            }
            catch { return new List<Pending>(); }
        }

        void WritePending(List<Pending> items)
        {
            if (items.Count == 0) { if (File.Exists(pendingPath)) File.Delete(pendingPath); return; }
            var tmp = pendingPath + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(items));
            File.Move(tmp, pendingPath, true);
        }

        void Keep(string system, string name, string json)
        {
            var items = ReadPending();
            items.RemoveAll(p => p.System == system && p.Name == name);   // the newest details win
            items.Add(new Pending { System = system, Name = name, Json = json });
            WritePending(items.Skip(Math.Max(0, items.Count - 200)).ToList());
        }

        internal async Task SendPendingAsync(CancellationToken cancel)
        {
            var items = ReadPending();
            if (items.Count == 0) return;
            var left = new List<Pending>();
            foreach (var p in items)
            {
                try
                {
                    var code = await SendMetaAsync(p.System, p.Name, p.Json, cancel).ConfigureAwait(false);
                    if (code == 404) left.Add(p);
                    else log($"sent saved details for {p.System}/{p.Name} ({code})");
                }
                catch { left.Add(p); }
            }
            WritePending(left);
        }

        // ---- hi2txt ---------------------------------------------------------------------------

        /// <summary>The arguments for hi2txt, with {file}, {dat}, {game} and {system} filled in.</summary>
        internal IEnumerable<string> Hi2txtArgs(ChangedFile file)
        {
            settings.HiscoreDat.TryGetValue(file.System, out var dat);
            var template = settings.Hi2txtArgs is { Count: > 0 }
                ? settings.Hi2txtArgs
                : string.IsNullOrWhiteSpace(dat)
                    ? new List<string> { "-r", "{file}" }
                    : new List<string> { "-hiscoredat", "{dat}", "-r", "{file}" };
            var game = Path.GetFileNameWithoutExtension(file.FullPath);
            return template.Select(a => a.Replace("{file}", file.FullPath).Replace("{dat}", dat ?? "")
                                         .Replace("{game}", game).Replace("{system}", file.System));
        }

        /// <summary>hi2txt's text output for the file, or null if hi2txt isn't set up or can't read it.</summary>
        string RunHi2txt(ChangedFile file)
        {
            if (string.IsNullOrWhiteSpace(settings.Hi2txt) || !File.Exists(settings.Hi2txt)) return null;
            try
            {
                var psi = new ProcessStartInfo(settings.Hi2txt)
                {
                    UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardOutput = true, RedirectStandardError = true,
                    WorkingDirectory = Path.GetDirectoryName(settings.Hi2txt),
                };
                foreach (var a in Hi2txtArgs(file)) psi.ArgumentList.Add(a);
                using var p = Process.Start(psi);
                var stdout = p.StandardOutput.ReadToEndAsync();
                var stderr = p.StandardError.ReadToEndAsync();
                if (!p.WaitForExit(10000))
                {
                    try { p.Kill(true); } catch { }
                    log($"hi2txt took too long on {file.Name}");
                    return null;
                }
                var text = stdout.Result;
                if (p.ExitCode != 0 || string.IsNullOrWhiteSpace(text))
                {
                    log($"hi2txt can't read {file.System}/{file.Name} (exit {p.ExitCode}) {stderr.Result.Trim()}");
                    return null;
                }
                return text.Length > 32000 ? text.Substring(0, 32000) : text;
            }
            catch (Exception e)
            {
                log("hi2txt failed: " + e.Message);
                return null;
            }
        }
    }
}
