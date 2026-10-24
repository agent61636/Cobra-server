using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace CobraHiscore
{
    /// <summary>One folder the agent watches for .hi files (same shape as the agent's config.json).</summary>
    internal sealed class WatchFolder
    {
        public string Path { get; set; }
        public string System { get; set; }
    }

    /// <summary>
    /// The plugin's settings. The server address, the watched folders and the API key are
    /// read from the hiscore agent's folder, so both always agree; the plugin's own
    /// config.json adds only what the agent doesn't need (hi2txt).
    /// </summary>
    internal sealed class Settings
    {
        public string AgentFolder { get; set; } = @"C:\Cobra\hiscore-agent";
        public string Server { get; set; }
        public List<WatchFolder> Folders { get; set; } = new List<WatchFolder>();
        public string Hi2txt { get; set; }
        public List<string> Hi2txtArgs { get; set; }
        public Dictionary<string, string> HiscoreDat { get; set; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public int SettleSeconds { get; set; } = 3;

        static readonly JsonSerializerOptions Json = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };

        public static Settings Load(string pluginFolder)
        {
            var settings = new Settings();
            var own = System.IO.Path.Combine(pluginFolder, "config.json");
            if (File.Exists(own))
            {
                var mine = JsonSerializer.Deserialize<Settings>(File.ReadAllText(own), Json);
                if (mine != null)
                {
                    settings = mine;
                    settings.HiscoreDat = new Dictionary<string, string>(
                        settings.HiscoreDat ?? new Dictionary<string, string>(), StringComparer.OrdinalIgnoreCase);
                }
            }

            var agent = System.IO.Path.Combine(settings.AgentFolder ?? "", "config.json");
            if (File.Exists(agent))
            {
                var theirs = JsonSerializer.Deserialize<Settings>(File.ReadAllText(agent), Json);
                if (theirs != null)
                {
                    if (string.IsNullOrWhiteSpace(settings.Server)) settings.Server = theirs.Server;
                    if (settings.Folders == null || settings.Folders.Count == 0) settings.Folders = theirs.Folders;
                }
            }
            settings.Folders ??= new List<WatchFolder>();
            if (settings.SettleSeconds < 0 || settings.SettleSeconds > 60) settings.SettleSeconds = 3;
            return settings;
        }

        public string KeyPath => System.IO.Path.Combine(AgentFolder ?? "", "key.dat");
    }
}
