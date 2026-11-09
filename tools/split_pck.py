#!/usr/bin/env python3
"""Split the exported web pack in two, so the browser starts fast.

    python3 tools/split_pck.py <export dir>     (the folder with index.html)

Godot exports one index.pck with everything in it (~100 MB). The browser has
to download all of it before the Godot splash goes away. This splits it:

  index.pck  the boot pack: every script, the data files, the UI, fonts,
             icons and the character models. Enough for the title screen,
             character select and the character creator (game/boot/lobby.gd).
  game.pck   the world: terrain textures, trees, rocks, plants, sounds and
             the map paintings. lobby.gd downloads it in the background while
             you pick or make a character and loads it when you enter the
             world (ProjectSettings.load_resource_pack).

A resource goes to game.pck with its .import/.remap file and everything that
file points at, so in the boot pack it simply does not exist yet
(ResourceLoader.exists is false) instead of failing to load.

The rules are path prefixes in GAME_PACK below; keep lobby.GAME_MARKER inside
them. index.html's fileSizes (its loading bar) is updated to the new size.
"""
import os
import re
import struct
import sys

# source paths (under res://) whose resources wait for game.pck
GAME_PACK = (
    "assets/environment/",
    "assets/sounds/",
)
# images under these go to game.pck too (the map paintings); the terrain's
# data files stay in the boot pack because the database reads them at start
GAME_PACK_IMAGES = ("data/terrain/",)
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp")
# must end up in game.pck: lobby.gd looks for it to tell the packs apart
MARKER = "assets/environment/nature/trees/Pine_1.gltf"

ALIGN = 32


def read_pck(path):
    d = open(path, "rb").read()
    if d[:4] != b"GDPC":
        sys.exit("%s is not a Godot pack" % path)
    ver, major, minor, patch, flags, base, diro = struct.unpack_from("<IIIIIQQ", d, 4)
    if ver < 3 or not flags & 2:
        sys.exit("unsupported pack format %d (flags %d)" % (ver, flags))
    if flags & 1:
        sys.exit("encrypted packs are not supported")
    off = diro
    (n,) = struct.unpack_from("<I", d, off)
    off += 4
    files = []
    for _ in range(n):
        (ln,) = struct.unpack_from("<I", d, off)
        off += 4
        name = d[off:off + ln].rstrip(b"\0").decode()
        off += ln
        o, s = struct.unpack_from("<QQ", d, off)
        md5 = d[off + 16:off + 32]
        (fl,) = struct.unpack_from("<I", d, off + 32)
        off += 36
        files.append({"path": name, "data": d[base + o:base + o + s], "md5": md5, "flags": fl})
    return (ver, major, minor, patch, flags), files


def write_pck(path, head, files):
    ver, major, minor, patch, flags = head
    header = bytearray(struct.pack("<4sIIIIIQQ", b"GDPC", ver, major, minor, patch, flags, 0, 0))
    header += b"\0" * (16 * 4) # reserved
    base = (len(header) + ALIGN - 1) // ALIGN * ALIGN
    body = bytearray()
    offsets = []
    for f in files:
        offsets.append(len(body))
        body += f["data"]
        body += b"\0" * ((-(base + len(body))) % ALIGN)
    diro = base + len(body)
    dirb = bytearray(struct.pack("<I", len(files)))
    for f, o in zip(files, offsets):
        name = f["path"].encode()
        pad = 4 - len(name) % 4 # always at least one terminating zero
        dirb += struct.pack("<I", len(name) + pad) + name + b"\0" * pad
        dirb += struct.pack("<QQ", o, len(f["data"])) + f["md5"] + struct.pack("<I", f["flags"])
    struct.pack_into("<QQ", header, 24, base, diro)
    header += b"\0" * (base - len(header))
    with open(path, "wb") as out:
        out.write(header)
        out.write(body)
        out.write(dirb)


def goes_to_game(src):
    if src.startswith(GAME_PACK):
        return True
    return src.startswith(GAME_PACK_IMAGES) and src.lower().endswith(IMAGE_EXT)


def split(files):
    by_path = {f["path"]: f for f in files}
    # what each .import / .remap file points at (res://.godot/imported/...)
    owner = {}
    for f in files:
        p = f["path"]
        if p.endswith(".import") or p.endswith(".remap"):
            src = p.rsplit(".", 1)[0]
            for dest in re.findall(r'"res://([^"]+)"', f["data"].decode("utf-8", "replace")):
                if dest.startswith(".godot/") and dest in by_path:
                    owner[dest] = src
            owner[p] = src
    boot, game = [], []
    for f in files:
        src = owner.get(f["path"], f["path"])
        (game if goes_to_game(src) else boot).append(f)
    return boot, game


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    index = os.path.join(out_dir, "index.pck")
    head, files = read_pck(index)
    boot, game = split(files)
    names = {f["path"] for f in game}
    if MARKER + ".import" not in names:
        sys.exit("the marker %s is not in game.pck: check GAME_PACK" % MARKER)
    write_pck(os.path.join(out_dir, "game.pck"), head, game)
    write_pck(index, head, boot)
    size = os.path.getsize(index)
    html = os.path.join(out_dir, "index.html")
    if os.path.exists(html):
        text = open(html, encoding="utf-8").read()
        text, n = re.subn(r'("index\.pck"\s*:\s*)\d+', lambda m: m.group(1) + str(size), text)
        if n == 0:
            print("warning: no index.pck size in index.html")
        # the lobby's progress bar: a browser fetch does not always say
        size_tag = '<script>window.gamePckSize = %d;</script>' % os.path.getsize(os.path.join(out_dir, "game.pck"))
        text = re.sub(r'<script>window\.gamePckSize = \d+;</script>', "", text)
        text = text.replace("</head>", size_tag + "</head>", 1)
        open(html, "w", encoding="utf-8").write(text)
    mb = lambda fs: sum(len(f["data"]) for f in fs) / 1e6
    print("boot index.pck %.1f MB (%d files), game.pck %.1f MB (%d files)" % (mb(boot), len(boot), mb(game), len(game)))


if __name__ == "__main__":
    main()
