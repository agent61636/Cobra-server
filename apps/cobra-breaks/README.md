# cobra-breaks

Builds a **"&lt;Show&gt; — with breaks"** playlist in Jellyfin for each show and user you list: episode, a random filler video, episode, another filler video, and so on. Playlists are a normal Jellyfin feature, so they play on every app, including Roku and Apple TV, where a plugin that injects intros can't reach episodes.

- Starts at each user's **next unwatched** episode and rebuilds daily, so the playlist follows along as you watch, with new filler each day.
- Every break in one playlist is a **different** video. Jellyfin drops repeated items from a playlist, so when there's too little filler for the whole run, the playlist is shortened instead of losing breaks, and the log says so.
- An existing playlist is updated in place, keeping the same Jellyfin ID.
- Python standard library only; runs in the `stream` pod next to Jellyfin (manual part 6).

Config: `breaks.example.toml`. Tests: `python3 -m unittest discover -s tests` (12 tests, including an end-to-end run against a fake Jellyfin that behaves like the real one: it drops repeated playlist items, and its "update playlist" call refuses API keys).
