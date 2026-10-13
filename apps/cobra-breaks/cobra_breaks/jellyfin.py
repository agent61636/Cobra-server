"""Small Jellyfin REST client (standard library only).

Uses an API key from Dashboard -> API Keys. Endpoints used:
  GET  /Users
  GET  /Library/VirtualFolders
  GET  /Items                      (series, filler videos, existing playlists)
  GET  /Shows/{seriesId}/Episodes
  POST /Playlists                  (create, with the items)
  GET/DELETE/POST /Playlists/{id}/Items   (replace the items of an existing one)
"""

import json
import urllib.error
import urllib.parse
import urllib.request


class JellyfinError(RuntimeError):
    pass


class Jellyfin:
    def __init__(self, url, api_key, timeout=30):
        self.url = url.rstrip("/")
        self.key = api_key
        self.timeout = timeout
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def _call(self, method, path, query=None, body=None):
        q = {k: v for k, v in (query or {}).items() if v is not None}
        url = self.url + path + ("?" + urllib.parse.urlencode(q) if q else "")
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f'MediaBrowser Token="{self.key}"',
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        try:
            with self.opener.open(req, timeout=self.timeout) as r:
                raw = r.read()
        except urllib.error.HTTPError as e:
            raise JellyfinError(f"{method} {path}: HTTP {e.code} {e.read()[:200]!r}") from None
        except urllib.error.URLError as e:
            raise JellyfinError(f"{method} {path}: {e.reason}") from None
        return json.loads(raw) if raw else None

    def users(self):
        return {u["Name"].lower(): u["Id"] for u in self._call("GET", "/Users")}

    def library_id(self, name):
        for f in self._call("GET", "/Library/VirtualFolders"):
            if f.get("Name", "").lower() == name.lower():
                return f["ItemId"]
        raise JellyfinError(f"no library named {name!r} (Dashboard -> Libraries)")

    def items(self, **query):
        q = {"recursive": "true", **query}
        out, start = [], 0
        while True:
            page = self._call("GET", "/Items", {**q, "startIndex": start, "limit": 500})
            batch = page.get("Items", [])
            out.extend(batch)
            start += len(batch)
            if not batch or start >= page.get("TotalRecordCount", 0):
                return out

    def find_series(self, name, user_id):
        hits = self.items(includeItemTypes="Series", searchTerm=name, userId=user_id)
        exact = [h for h in hits if h.get("Name", "").lower() == name.lower()]
        if not exact:
            raise JellyfinError(f"no series named {name!r} visible to that user")
        return exact[0]["Id"]

    def episodes(self, series_id, user_id):
        page = self._call("GET", f"/Shows/{series_id}/Episodes",
                          {"userId": user_id, "fields": "Path", "enableUserData": "true",
                           "isMissing": "false"})
        return page.get("Items", [])

    def filler(self, library_id, user_id):
        return self.items(parentId=library_id, includeItemTypes="Video,Movie,MusicVideo",
                          fields="Path", userId=user_id)

    def playlist_id(self, name, user_id):
        for p in self.items(includeItemTypes="Playlist", userId=user_id):
            if p.get("Name") == name:
                return p["Id"]
        return None

    def set_playlist(self, name, user_id, ids, batch=40):
        """Create the playlist, or replace the items of an existing one (same Id, so
        shortcuts and 'continue watching' on the TV keep pointing at it).

        Replacing goes through the item endpoints: Jellyfin's "update playlist"
        call only accepts the owner's own login, while removing entries works
        with an API key and adding works with an API key plus the owner's userId.
        """
        pid = self.playlist_id(name, user_id)
        if pid is None:
            res = self._call("POST", "/Playlists",
                             body={"Name": name, "Ids": ids, "UserId": user_id, "MediaType": "Video"})
            return res["Id"], True
        page = self._call("GET", f"/Playlists/{pid}/Items", {"userId": user_id})
        entries = [i["PlaylistItemId"] for i in (page or {}).get("Items", []) if i.get("PlaylistItemId")]
        for k in range(0, len(entries), batch):
            self._call("DELETE", f"/Playlists/{pid}/Items", {"entryIds": ",".join(entries[k:k + batch])})
        for k in range(0, len(ids), batch):
            self._call("POST", f"/Playlists/{pid}/Items", {"ids": ",".join(ids[k:k + batch]), "userId": user_id})
        return pid, False
