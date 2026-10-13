# Song of Eo radio: an always-on station shuffled from the music library.
# Liquidsoap 2.x. Plays to Icecast in the same pod (127.0.0.1:8000, mount /stream).

settings.log.stdout.set(true)
settings.log.file.set(false)

music_dir = environment.get(default="/media/music", "RADIO_MUSIC")
password  = environment.get("ICECAST_SOURCE_PASSWORD")
station   = environment.get(default="Song of Eo Radio", "RADIO_NAME")

# Shuffle every track under the folder; pick up new files without a restart.
music = playlist(mode="randomize", reload_mode="watch", music_dir)

# Smooth hand-offs between songs, and silence instead of a crash if a file is bad.
radio = crossfade(duration=4., music)
radio = mksafe(radio)

output.icecast(
  %mp3(bitrate=192),
  host="127.0.0.1", port=8000, password=password,
  mount="/stream", name=station, description="Shuffled from our library",
  radio)
