"""Builds the landing site into a folder next to the web export.

    python3 tools/build_site.py _site

Copies site/ into the folder, fills the shared header, sidebar and footer,
renders the Classes page from data/ui/text.json (title.classes, only classes
with an archetype) and data/abilities/archetypes.json / abilities.json, and copies the
bronze UI kit, class crests and spell icons the pages use. The game itself is
exported to <folder>/play by the Pages workflow.
"""
import html
import re
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "_site")
KIT = ["button", "button_hover", "panel", "window"]


def load(name):
    """A data file by its flat name; data/catalogue.json says which folder it lives in."""
    data = os.path.join(ROOT, "data")
    path = os.path.join(data, name)
    catalogue = os.path.join(data, "catalogue.json")
    if not os.path.exists(path) and os.path.exists(catalogue):
        with open(catalogue, encoding="utf-8") as f:
            files = json.load(f).get("files", {})
        path = os.path.join(data, files.get(name[:-5], name))
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def crest(class_id):
    return "class_" + ("warrior" if class_id == "warden" else class_id)


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def main():
    text = load("text.json")["title"]
    archetypes = {a["id"]: a for a in load("archetypes.json")["archetypes"]}
    abilities = {a["id"]: a for a in load("abilities.json")["abilities"]}
    classes = [c for c in text["classes"] if c.get("archetype") in archetypes]
    build = {}
    if os.path.exists(os.path.join(ROOT, "data", "build.json")):
        build = load("build.json")
    e = html.escape

    head = ('<link rel="preconnect" href="https://fonts.googleapis.com">\n'
            '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
            '<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700&family=Crimson+Text:ital,wght@0,400;0,600;1,400&display=swap" rel="stylesheet" media="print" onload="this.media=\'all\'">\n'
            '<link rel="stylesheet" href="style.css">\n<link rel="icon" href="kit/crest.png">')

    def header(page):
        links = [("index.html", "Home", "home"), ("news.html", "News", "news"),
                 ("story.html", "Game Guide", "guide"), ("play/", "Play", "")]
        nav = "".join('<a class="btn%s" href="%s">%s</a>' % (" on" if p == page else "", h, t) for h, t, p in links)
        return ('<header class="banner wrap"><a href="index.html" class="logo"><img src="kit/crest.png" alt="">'
                '<h1>SHADOWFALL</h1></a><div class="tag">%s &middot; %s</div><nav class="top">%s</nav></header>'
                % (e(text["tagline"]), e(text["build"]), nav))

    crests = "".join('<a href="classes.html#%s" title="%s"><img src="kit/%s.png" alt="%s"></a>'
                     % (c["id"], e(c["name"]), crest(c["id"]), e(c["name"])) for c in classes)
    aside = ('<aside><div class="box panel"><a class="play" href="play/">PLAY NOW<small>Free in your browser</small></a>'
             '<p class="note">Best on a desktop browser with keyboard and mouse, or a gamepad. The first load is about 20 MB.</p></div>'
             '<div class="box panel side"><h3>News</h3><ul><li><a href="index.html#news">Current News</a></li>'
             '<li><a href="news.html">Archived News</a></li></ul></div>'
             '<div class="box panel side"><h3>Game Guide</h3><ul><li><a href="story.html">Introduction</a></li>'
             '<li><a href="guide.html">Getting Started</a></li><li><a href="classes.html">Character</a></li></ul>'
             '<div class="crests">%s</div></div></aside>' % crests)
    stamp = " &middot; build %s, %s" % (e(build["commit"]), e(build["time"])) if build.get("commit") else ""
    footer = '<footer class="wrap">Mythkeep %s%s &middot; still on the anvil</footer>' % (e(text["build"]), stamp)

    cards = []
    icons = set()
    for c in classes:
        a = archetypes[c["archetype"]]
        kit = [a["bar"][0]] + [t["ability"] for t in a.get("trained", [])]
        spells = []
        for sid in kit:
            if sid not in abilities:
                continue
            icon = os.path.join(ROOT, "assets", "icons", "spells", sid + ".png")
            img = ""
            if os.path.exists(icon):
                icons.add(sid)
                img = '<img src="kit/spells/%s.png" alt="" loading="lazy">' % sid
            spells.append("<figure>%s%s</figure>" % (img, e(abilities[sid]["name"])))
        stat, armour, resource, sw = (c["traits"] + ["", "", "", ""])[:4]
        rows = [("Main stat", stat), ("Armour", armour), ("Resource", resource), ("Trait", a["trait"]["name"])]
        if sw:
            rows.append(("In a fight", sw))
        dl = "".join("<dt>%s</dt><dd>%s</dd>" % (k, e(v)) for k, v in rows if v)
        cards.append('<section class="box" id="%s"><div class="class"><img src="kit/%s.png" alt="">'
                     '<div><h2>%s</h2><div class="role">%s</div><p>%s</p><dl>%s</dl>'
                     '<h3>First abilities</h3><div class="spells">%s</div></div></div></section>'
                     % (c["id"], crest(c["id"]), e(c["name"]), e(c["role"]), e(c["blurb"]), dl, "".join(spells)))

    with open(os.path.join(ROOT, "site", "news.html"), encoding="utf-8") as f:
        posts = re.findall(r"(?s)    <article>.*?</article>\n", f.read())

    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(os.path.join(ROOT, "site")):
        src = os.path.join(ROOT, "site", name)
        dst = os.path.join(OUT, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst, dirs_exist_ok=True)
        elif name.endswith(".html"):
            with open(src, encoding="utf-8") as f:
                page = f.read()
            for p in ("home", "news"):
                page = page.replace("<!--HEADER:%s-->" % p, header(p))
            for p in ("classes", "story", "guide"):
                page = page.replace("<!--HEADER:%s-->" % p, header("guide"))
            page = page.replace("<!--NEWS:3-->", "".join(posts[:3]))
            page = (page.replace("<!--HEAD-->", head).replace("<!--ASIDE-->", aside)
                    .replace("<!--FOOTER-->", footer).replace("<!--CLASSES-->", "\n".join(cards)))
            with open(dst, "w", encoding="utf-8") as f:
                f.write(page)
        else:
            shutil.copyfile(src, dst)

    for k in KIT:
        copy(os.path.join(ROOT, "assets", "ui", k + ".png"), os.path.join(OUT, "kit", k + ".png"))
    copy(os.path.join(ROOT, "assets", "icons", "ui", "crest.png"), os.path.join(OUT, "kit", "crest.png"))
    for c in classes:
        copy(os.path.join(ROOT, "assets", "icons", "ui", crest(c["id"]) + ".png"), os.path.join(OUT, "kit", crest(c["id"]) + ".png"))
    for sid in icons:
        copy(os.path.join(ROOT, "assets", "icons", "spells", sid + ".png"), os.path.join(OUT, "kit", "spells", sid + ".png"))
    print("site: %d classes, %d spell icons -> %s" % (len(classes), len(icons), OUT))


if __name__ == "__main__":
    main()
