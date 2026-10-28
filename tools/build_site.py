"""Builds the landing site into a folder next to the web export.

    python3 tools/build_site.py _site

Copies site/ into the folder, fills the shared header, sidebar and footer,
renders the Classes page from data/text.json (title.classes, only classes
with an archetype) and data/archetypes.json / abilities.json, and copies the
bronze UI kit, class crests and spell icons the pages use. The game itself is
exported to <folder>/play by the Pages workflow.
"""
import html
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "_site")
KIT = ["button", "button_hover", "panel", "window"]


def load(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
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
        links = [("index.html", "Home", "home"), ("index.html#about", "The Game", ""),
                 ("classes.html", "Classes", "classes"), ("index.html#news", "News", ""), ("play/", "Play", "")]
        nav = "".join('<a class="btn%s" href="%s">%s</a>' % (" on" if p == page else "", h, t) for h, t, p in links)
        return ('<header class="banner wrap"><a href="index.html" class="logo"><img src="kit/crest.png" alt="">'
                '<h1>SHADOWFALL</h1></a><div class="tag">%s &middot; %s</div><nav class="top">%s</nav></header>'
                % (e(text["tagline"]), e(text["build"]), nav))

    crests = "".join('<a href="classes.html#%s" title="%s"><img src="kit/%s.png" alt="%s"></a>'
                     % (c["id"], e(c["name"]), crest(c["id"]), e(c["name"])) for c in classes)
    aside = ('<aside><div class="box panel"><a class="play" href="play/">PLAY NOW<small>Free in your browser</small></a>'
             '<p class="note">Best on a desktop browser with keyboard and mouse, or a gamepad. The first load is about 20 MB.</p></div>'
             '<div class="box panel"><h3>Classes</h3><div class="crests">%s</div></div>'
             '<div class="box panel"><h3>First Steps</h3><ul>'
             '<li><b>WASD</b> or stick to move</li><li><b>Left click</b> selects</li>'
             '<li><b>Right click</b> talks and loots</li><li><b>Number keys</b> use abilities</li>'
             '<li>Every key can be rebound in Settings</li></ul></div></aside>' % crests)
    stamp = " &middot; build %s, %s" % (e(build["commit"]), e(build["time"])) if build.get("commit") else ""
    footer = '<footer class="wrap">Shadowfall %s%s &middot; still on the anvil</footer>' % (e(text["build"]), stamp)

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

    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(os.path.join(ROOT, "site")):
        src = os.path.join(ROOT, "site", name)
        dst = os.path.join(OUT, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst, dirs_exist_ok=True)
        elif name.endswith(".html"):
            with open(src, encoding="utf-8") as f:
                page = f.read()
            for p in ("home", "classes"):
                page = page.replace("<!--HEADER:%s-->" % p, header(p))
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
