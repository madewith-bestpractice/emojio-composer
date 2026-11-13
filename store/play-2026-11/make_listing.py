"""Builds the next Play listing (listing.json) from the text in review (listing-in-review.json).

Per language it swaps in a search-aware opening (heading + first paragraph) and short
description, and rewrites the share-link bullet: on Android a shared link opens the web
player, not the app, so the old "opens right back up in Emojio" line over-promised.
Titles stay as they are unless titles.json names one. Everything else is unchanged.

    python3 -I make_listing.py            # writes listing.json, checks Play limits and banned words
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = json.loads((HERE / "listing-in-review.json").read_text(encoding="utf-8"))
TITLES = json.loads((HERE / "titles.json").read_text(encoding="utf-8")) if (HERE / "titles.json").exists() else {}

ES = {
    "short": "Haz música con emoji: crea canciones y ritmos. Para niños y principiantes",
    "head": "UN CREADOR DE MÚSICA CON EMOJI PARA NIÑOS, FAMILIAS Y PRINCIPIANTES.",
    "intro": "Emojio es una app para crear música donde cada emoji es un instrumento. Toca una rana, un perro, un tambor o una campana, coloca los stickers en el pentagrama y tu canción empieza a sonar. Haz ritmos y beats con la batería, escribe una melodía y compón una canción entera en minutos. No necesitas leer notas ni saber teoría: si puedes elegir un emoji, puedes hacer música.",
    "share": ("• Comparte un enlace que abre tu canción directo en Emojio.",
              "• Comparte un enlace: cualquiera puede abrir y escuchar tu canción en el navegador, sin instalar nada."),
}
NEW = {
    "en-US": {
        "short": "Make music with emoji: a song & beat maker for kids, families and beginners",
        "head": "AN EMOJI MUSIC MAKER FOR KIDS, FAMILIES AND BEGINNERS.",
        "intro": "Emojio is a music maker where every emoji is an instrument. Tap a frog, a dog, a drum or a bell, drop the stickers onto the staff, and your song plays. Make beats with the drum kit, write a melody, and compose a whole little song in minutes. It's a song maker and a beat maker in one, with no notes to read and no theory to learn. If you can pick an emoji, you can make music.",
        "share": ("• Share a link that opens your song right back up in Emojio.",
                  "• Share a link: anyone can open and play your song in a web browser, no app needed."),
    },
    "es-419": ES,
    "es-US": ES,
    "pt-BR": {
        "short": "Faça música com emoji: crie músicas e batidas. Para crianças e iniciantes",
        "head": "UM CRIADOR DE MÚSICA COM EMOJI PARA CRIANÇAS, FAMÍLIAS E INICIANTES.",
        "intro": "O Emojio é um app para fazer música em que cada emoji é um instrumento. Toque num sapo, num cachorro, num tambor ou num sino, coloque as figurinhas na pauta e sua música começa a tocar. Faça batidas e beats com a bateria, escreva uma melodia e componha uma música inteira em minutos. Não precisa ler partitura nem saber teoria: se você sabe escolher um emoji, sabe fazer música.",
        "share": ("• Compartilhe um link que abre sua música direto no Emojio.",
                  "• Compartilhe um link: qualquer pessoa abre e ouve sua música no navegador, sem instalar nada."),
    },
    "ja-JP": {
        "short": "絵文字で作曲!子どもも初心者も、五線譜にスタンプを置いて曲やビートを作れる音楽アプリ",
        "head": "子どもから大人まで。絵文字で作曲できる音楽アプリ。",
        "intro": "Emojio は、どの絵文字も楽器になる作曲アプリです。カエル、イヌ、ドラム、ベル……絵文字のスタンプを五線譜に置くだけで曲が鳴りだします。ドラムでリズムやビートを作り、メロディを書いて、数分で1曲完成。楽譜が読めなくても、音楽理論を知らなくても大丈夫。はじめての作曲にもぴったりです。",
        "share": ("• リンクを送れば、相手の Emojio であなたの曲がそのまま開きます。",
                  "• リンクを送れば、アプリがなくてもブラウザであなたの曲を開いて聴けます。"),
    },
    "de-DE": {
        "short": "Musik machen mit Emoji: Songs und Beats bauen. Für Kinder und Einsteiger",
        "head": "MUSIK MACHEN MIT EMOJI – FÜR KINDER, FAMILIEN UND EINSTEIGER.",
        "intro": "Emojio ist eine Musik-App, in der jedes Emoji ein Instrument ist. Tipp auf einen Frosch, einen Hund, eine Trommel oder eine Glocke, setz die Sticker auf die Notenlinien und dein Song spielt los. Bau Beats mit dem Schlagzeug, schreib eine Melodie und komponiere in wenigen Minuten einen ganzen Song. Keine Noten lesen, keine Musiktheorie: Wer ein Emoji aussuchen kann, kann Musik machen.",
        "share": ("• Teile einen Link, der deinen Song direkt in Emojio öffnet.",
                  "• Teile einen Link: Jeder kann deinen Song im Browser öffnen und anhören, ganz ohne App."),
    },
    "fr-FR": {
        "short": "Fais de la musique avec des emoji : chansons et beats, enfants et débutants",
        "head": "CRÉE DE LA MUSIQUE AVEC DES EMOJI, POUR ENFANTS, FAMILLES ET DÉBUTANTS.",
        "intro": "Emojio est une app pour faire de la musique où chaque emoji est un instrument. Choisis une grenouille, un chien, un tambour ou une cloche, pose les stickers sur la portée et ta chanson se met à jouer. Fais des beats et des rythmes avec la batterie, écris une mélodie et compose une chanson entière en quelques minutes. Pas besoin de lire les notes ni de connaître la théorie : si tu sais choisir un emoji, tu sais faire de la musique.",
        "share": ("• Partage un lien qui rouvre ta chanson directement dans Emojio.",
                  "• Partage un lien : n'importe qui peut ouvrir et écouter ta chanson dans un navigateur, sans l'app."),
    },
    "ko-KR": {
        "short": "이모지로 작곡하기! 아이도 초보자도 오선지에 스티커를 놓아 노래와 비트를 만들어요",
        "head": "아이부터 어른까지, 이모지로 만드는 음악.",
        "intro": "Emojio는 모든 이모지가 악기가 되는 작곡 앱이에요. 개구리, 강아지, 드럼, 종… 이모지 스티커를 오선지에 올려놓으면 노래가 흘러나와요. 드럼으로 리듬과 비트를 만들고, 멜로디를 쓰고, 몇 분 만에 노래 한 곡을 완성해 보세요. 악보를 몰라도, 음악 이론을 몰라도 괜찮아요. 처음 하는 작곡에도 딱 좋아요.",
        "share": ("• 링크를 공유하면 받는 사람의 Emojio에서 노래가 그대로 열려요.",
                  "• 링크를 공유하면 앱이 없어도 누구나 브라우저에서 노래를 열어 들을 수 있어요."),
    },
}
BANNED = ("free", "gratis", "grátis", "gratuit", "kostenlos", "無料", "무료", "best", "#1", "iPad", "iPhone", "Apple")

out = {}
for lang, src in SRC.items():
    n = NEW[lang]
    paras = src["fullDescription"].split("\n\n")
    paras[0], paras[1] = n["head"], n["intro"]
    full = "\n\n".join(paras)
    old, new = n["share"]
    assert full.count(old) == 1, (lang, "share bullet not found")
    full = full.replace(old, new)
    title = TITLES.get(lang, src["title"])
    out[lang] = {"title": title, "shortDescription": n["short"], "fullDescription": full}
    t, s = len(title), len(n["short"])
    assert t <= 30 and s <= 80 and len(full) <= 4000, (lang, t, s, len(full))
    low = (title + " " + n["short"] + " " + full).lower()
    hits = [b for b in BANNED if re.search(r"(?<!\w)" + re.escape(b.lower()) + r"(?!\w)", low)]
    assert not hits, (lang, hits)
    print(f"{lang:7} title[{t}] short[{s}] full[{len(full)}]  {title} | {n['short']}")

(HERE / "listing.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print("wrote", HERE / "listing.json")
