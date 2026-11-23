#!/usr/bin/env python3
"""Скачать исходные записи CC0 (freesound.org) для tools/audio/horror_sfx.py.

    python3 tools/audio/fetch_cc0.py            # в tools/audio/.cc0_cache/

Список, авторы и ссылки — tools/audio/cc0_sources.json. Все записи под лицензией
Creative Commons 0 (общественное достояние); берётся публичное превью высокого качества (mp3).
"""
import json, os, re, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.environ.get("CC0_CACHE", os.path.join(HERE, ".cc0_cache"))
UA = "Mozilla/5.0 (X11; Linux x86_64)"


def main():
    os.makedirs(CACHE, exist_ok=True)
    sources = json.load(open(os.path.join(HERE, "cc0_sources.json"), encoding="utf-8"))
    for key, items in sources.items():
        for item in items:
            path = os.path.join(CACHE, item["cache"])
            if os.path.exists(path):
                continue
            page = subprocess.run(["curl", "-s", "-m", "40", "-A", UA, item["url"]], capture_output=True, text=True).stdout
            if "publicdomain/zero" not in page and "Creative Commons 0" not in page:
                print("! лицензия изменилась, пропускаю", item["url"])
                continue
            m = re.search(r"https://cdn\.freesound\.org/previews/\d+/%d_\d+-[hl]q\.mp3" % item["freesound_id"], page)
            if not m:
                print("! нет превью", item["url"])
                continue
            subprocess.run(["curl", "-s", "-m", "60", "-A", UA, "-o", path, m.group(0).replace("-lq", "-hq")], check=True)
            print("ok", item["cache"], "—", item["title"], "by", item["author"])


if __name__ == "__main__":
    main()
