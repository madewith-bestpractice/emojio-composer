#!/usr/bin/env python3
"""Frames the raw store captures and lints their captions.

    python3 tool/store_shots/build.py              # every set
    python3 tool/store_shots/build.py appstore-ipad

Reads shots.json and RAW/<device>/<frame>.png (see capture.sh), lays each frame
into templates/frame.html with headless Google Chrome, and writes exact-size
RGB PNGs (no alpha) to OUT/<set>/NN-<frame>.png, plus a contact sheet per set
in OUT/review/. Each set's folder is cleared first, so a reordered set never
uploads a stale frame. Fails, naming the frame, on a banned caption word or a
missing capture. Adapted from Rithmatic's tool/store_shots/build.py.
"""
from __future__ import annotations

import base64, io, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
APP = HERE.parent.parent
WORK = Path(os.environ.get("STORE_SHOTS_WORK", "/Volumes/GetawayCar/tmp/emojio-shots"))
RAW, OUT = WORK / "raw", WORK / "out"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Google bans these in screenshot text; Apple rejects other platforms' names.
BANNED = {
    "play": re.compile(r"\b(free|new|best|top|sale|download|install)\b|#1|[$€£¥]", re.I),
    "appstore": re.compile(r"\b(android|google)\b|[$€£¥]", re.I),
}


def lint(store, frame, text):
    plain = re.sub(r"<[^>]+>|&\w+;", " ", " ".join(text.values()))
    hit = BANNED[store].search(plain)
    if hit:
        sys.exit(f"{frame} ({store}): '{hit.group(0)}' is not allowed in a caption")


def data_uri(im):
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def render(html, w, h, dest):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html)
        page = f.name
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", f"--window-size={w},{h}",
                    "--virtual-time-budget=3000",
                    f"--screenshot={dest}", f"file://{page}"],
                   check=True, capture_output=True)
    os.unlink(page)
    im = Image.open(dest).convert("RGB")
    if im.size != (w, h):
        sys.exit(f"{dest}: rendered {im.size}, wanted {(w, h)}")
    im.save(dest, "PNG")


def build(name, spec, frames):
    w, h = spec["size"]
    portrait = h > w
    unit = (w / 34) if portrait else (h / 46)
    caption = h * (0.22 if portrait else 0.25)
    template = (HERE / "templates" / "frame.html").read_text()
    out = OUT / name
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    made = []
    for n, frame in enumerate(spec["frames"], 1):
        f = frames[frame]
        subline = f["subline"]
        if spec["store"] == "play":
            subline = f.get("subline_play", subline)
        elif spec["raw"] == "mac":
            subline = f.get("subline_mac", subline)
        text = {"eyebrow": f["eyebrow"], "headline": f["headline"], "subline": subline}
        lint(spec["store"], frame, text)
        src = RAW / spec["raw"] / f"{frame}.png"
        if not src.exists():
            sys.exit(f"{name}: no capture for {frame} at {src}")
        im = Image.open(src).convert("RGB")
        if spec.get("crop_top"):  # drop the iOS status bar for Play
            im = im.crop((0, int(im.height * spec["crop_top"]), im.width, im.height))
        aspect = im.width / im.height
        card_w = w * (0.84 if portrait else 0.86)  # the page shrinks it to fit
        html = template
        for key, value in {
            "fonts": f"file://{APP}/assets/fonts", "w": w, "h": h, "unit": f"{unit:.2f}",
            "caption": f"{caption:.0f}", "card_w": f"{card_w:.0f}",
            "badge": "inline-block" if f.get("premium") else "none",
            "aspect": f"{aspect:.5f}",
            "image": data_uri(im), **text,
        }.items():
            html = html.replace("{{" + key + "}}", str(value))
        dest = out / f"{n:02d}-{frame}.png"
        render(html, w, h, dest)
        made.append(dest)
        print("  ", dest.relative_to(OUT))
    thumbs = [Image.open(p) for p in made]
    tw = 420 if portrait else 640
    scaled = [t.resize((tw, int(t.height * tw / t.width))) for t in thumbs]
    cols = 6 if portrait else 3
    rows = (len(scaled) + cols - 1) // cols
    th = scaled[0].height
    sheet = Image.new("RGB", (cols * (tw + 16) + 16, rows * (th + 16) + 16), "white")
    for i, t in enumerate(scaled):
        sheet.paste(t, (16 + (i % cols) * (tw + 16), 16 + (i // cols) * (th + 16)))
    (OUT / "review").mkdir(exist_ok=True)
    sheet.save(OUT / "review" / f"{name}.png")


def main():
    config = json.loads((HERE / "shots.json").read_text())
    for name in sys.argv[1:] or list(config["sets"]):
        print(name)
        build(name, config["sets"][name], config["frames"])


if __name__ == "__main__":
    main()
