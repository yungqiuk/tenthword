#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Сборка словаря RU→EN в SQLite.

Два режима.

    python3 tools/build_dictionary.py --sample
        Быстрый: 120 слов из tools/seed_ru_en.txt, без сети, за секунду.
        Нужен, чтобы приложение запускалось и что-то показывало, пока
        собирается настоящий словарь.

    python3 tools/build_dictionary.py
        Полный: качает машинный разбор Викисловаря с kaikki.org и частотный
        список с GitHub, собирает 100+ тысяч лемм. 10–40 минут, ~1 ГБ трафика.
        Скачанное кладётся в Data/cache/ и переиспользуется.

Лицензии данных и обязательная атрибуция — в docs/DATA.md.
Схема таблиц — там же.
"""

import argparse
import io
import json
import os
import sqlite3
import sys
import urllib.request

# Машинный разбор английского Викисловаря: русские слова с английскими толкованиями.
# Структура сайта менялась — если ссылка отдаёт 404, зайдите на
# https://kaikki.org/dictionary/Russian/ и возьмите актуальную ссылку на .jsonl
WIKTIONARY_URL = "https://kaikki.org/dictionary/Russian/kaikki.org-dictionary-Russian.jsonl"

# Частотный список по субтитрам, лицензия MIT.
FREQUENCY_URL = ("https://raw.githubusercontent.com/hermitdave/FrequencyWords/"
                 "master/content/2018/ru/ru_50k.txt")

# Теги словоформ в kaikki. В таблицу исключений идут только настоящие
# словоформы: падежи, числа, времена, лица. Всё остальное — латинская
# транслитерация, ударная запись заголовка, служебные строки таблицы
# и производные слова (собачий, собачка, собачара) — в текст не попадает
# или попадает с другим значением.
FORM_TAGS_KEEP = {
    "nominative", "genitive", "dative", "accusative", "instrumental",
    "prepositional", "locative", "vocative", "partitive",
    "singular", "plural",
    "first-person", "second-person", "third-person",
    "past", "present", "future", "imperative", "infinitive",
    "participle", "gerund", "short-form", "comparative", "superlative",
}
FORM_TAGS_SKIP = {
    "romanization", "canonical", "table-tags", "inflection-template", "class",
    "adjective", "relational", "diminutive", "augmentative", "collective",
    "pejorative", "obsolete", "archaic", "dialectal", "error-unknown-tag",
}

# Комбинирующее ударение. В книгах его нет, а Викисловарь ставит его
# в каждой форме — без вычистки таблица не совпадёт с текстом ни разу.
STRESS_MARKS = "\u0301\u0300"

# Пометы, из-за которых значение не считается вторым самостоятельным:
# редкое, устаревшее, переносное. Иначе «яблоко» уезжает в многозначные
# из-за глазного яблока.
SENSE_TAGS_MINOR = {
    "obsolete", "archaic", "rare", "dialectal", "figuratively", "poetic",
    "dated", "historical", "slang", "colloquial", "vulgar", "humorous",
}

# Части речи kaikki → наши. Всё остальное отбрасывается.
POS_MAP = {
    "noun": "noun", "verb": "verb", "adj": "adjective", "adv": "adverb",
    "pron": "pronoun", "prep": "preposition", "conj": "conjunction",
    "particle": "particle", "num": "numeral", "intj": "interjection",
}

SCHEMA = """
CREATE TABLE entries (
    lemma     TEXT PRIMARY KEY,
    english   TEXT NOT NULL,   -- что подставляем в текст: bed
    gloss     TEXT NOT NULL,   -- что показываем в карточке: кровать, постель
    pos       TEXT NOT NULL,
    ambiguous INTEGER NOT NULL DEFAULT 0,
    note      TEXT
);
CREATE TABLE frequency (
    lemma TEXT PRIMARY KEY,
    rank  INTEGER NOT NULL     -- 1 = самое частое слово языка
);
CREATE TABLE lemma_overrides (
    form  TEXT PRIMARY KEY,    -- словоформа, которую NLTagger разбирает неверно
    lemma TEXT NOT NULL
);
CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


# ── Загрузка ──────────────────────────────────────────────────────────────────

def download(url, destination):
    if os.path.exists(destination) and os.path.getsize(destination) > 0:
        print("  уже скачано:", destination)
        return destination

    os.makedirs(os.path.dirname(destination), exist_ok=True)
    print("  качаю", url)
    temporary = destination + ".part"
    with urllib.request.urlopen(url) as response, open(temporary, "wb") as out:
        total = 0
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
            total += len(chunk)
            sys.stdout.write("\r  %.0f МБ" % (total / 1e6))
            sys.stdout.flush()
    print()
    os.replace(temporary, destination)
    return destination


# ── Разбор Викисловаря ────────────────────────────────────────────────────────

def clean_gloss(text):
    """Убирает пометы и оставляет читаемое толкование."""
    text = text.strip()
    # «(colloquial) bed» → «bed»
    while text.startswith("("):
        close = text.find(")")
        if close == -1:
            break
        text = text[close + 1:].strip()
    # «bed, cot (furniture)» → «bed, cot»
    if "(" in text:
        text = text[:text.index("(")].strip()
    return text.strip(" .;:,")


def primary_word(gloss, pos):
    """Первый термин толкования — его и подставляем в текст."""
    for separator in (";", ","):
        if separator in gloss:
            gloss = gloss.split(separator)[0]
    word = gloss.strip()
    lowered = word.lower()
    # Викисловарь толкует глаголы инфинитивом с частицей: «to run».
    # В книге «собака to run» читается как поломка, частицу срезаем.
    if pos == "verb" and lowered.startswith("to "):
        word = word[3:].strip()
    # Артикль в толковании существительного тоже лишний: «an apple» → «apple».
    elif pos in ("noun", "adjective"):
        for article in ("a ", "an ", "the "):
            if lowered.startswith(article):
                word = word[len(article):].strip()
                break
    return word


def strip_stress(text):
    """Убирает комбинирующее ударение: соба́ка → собака."""
    for mark in STRESS_MARKS:
        text = text.replace(mark, "")
    return text


def is_cyrillic(text):
    """Отсекает транслитерацию и латинские варианты написания."""
    return any("\u0400" <= ch <= "\u04FF" for ch in text)


def is_pre_reform(text):
    """Дореформенная орфография: собакъ, собакѣ. В современных книгах не встречается."""
    return text.endswith("ъ") or any(ch in text for ch in "ѣіѳѵ")


def is_minor_sense(sense):
    """
    Второстепенное значение: помечено как редкое или переносное, либо
    существует только внутри устойчивого сочетания — «eyeball (usually
    глазно́е я́блоко)». Такие значения не делают слово многозначным.
    """
    if set(sense.get("tags") or []) & SENSE_TAGS_MINOR:
        return True
    raw = " ".join(sense.get("raw_glosses") or sense.get("glosses") or [])
    lowered = raw.lower()
    if "usually" in lowered or "especially in" in lowered or "only in" in lowered:
        return True
    return False


def looks_ambiguous(senses):
    """
    У слова несколько несвязанных значений — переводить нельзя, без контекста
    выберем неверно. Признак грубый: два первых толкования не пересекаются
    ни одним словом.
    """
    senses = [s for s in senses if not is_minor_sense(s)] or senses
    meaningful = [clean_gloss(s["glosses"][0]) for s in senses
                  if s.get("glosses") and clean_gloss(s["glosses"][0])]
    if len(meaningful) < 2:
        return False
    first = set(meaningful[0].lower().replace(",", " ").split())
    second = set(meaningful[1].lower().replace(",", " ").split())
    return not (first & second)


def parse_wiktionary(path, limit=None):
    entries = {}
    overrides = {}
    lines = 0

    with io.open(path, encoding="utf-8") as source:
        for line in source:
            lines += 1
            if lines % 100000 == 0:
                sys.stdout.write("\r  разобрано строк: %d, лемм: %d" % (lines, len(entries)))
                sys.stdout.flush()
            if limit and len(entries) >= limit:
                break

            try:
                record = json.loads(line)
            except ValueError:
                continue

            lemma = (record.get("word") or "").strip().lower()
            pos = POS_MAP.get(record.get("pos"))
            senses = record.get("senses") or []
            if not lemma or not pos or not senses:
                continue
            if " " in lemma:        # словосочетания не подставляем в текст
                continue
            if lemma in entries:    # первая статья выигрывает
                continue

            glosses = [g for s in senses for g in (s.get("glosses") or [])]
            if not glosses:
                continue
            gloss = clean_gloss(glosses[0])
            english = primary_word(gloss, pos)
            if not english or not english.isascii():
                continue

            entries[lemma] = {
                "english": english,
                "gloss": gloss,
                "pos": pos,
                "ambiguous": 1 if looks_ambiguous(senses) else 0,
            }

            # Словоформы: пригодятся как исключения лемматизации.
            for form in record.get("forms") or []:
                text = strip_stress((form.get("form") or "").strip().lower())
                tags = set(form.get("tags") or [])
                if not text or text == lemma or " " in text or text in overrides:
                    continue
                if tags & FORM_TAGS_SKIP or not (tags & FORM_TAGS_KEEP):
                    continue
                if not is_cyrillic(text) or is_pre_reform(text):
                    continue
                overrides[text] = lemma

    print("\r  разобрано строк: %d, лемм: %d" % (lines, len(entries)))
    return entries, overrides


def parse_frequency(path, known_lemmas):
    """Ранг леммы = лучший ранг среди её словоформ."""
    ranks = {}
    with io.open(path, encoding="utf-8") as source:
        for position, line in enumerate(source, start=1):
            word = line.split(" ")[0].strip().lower()
            if word and word in known_lemmas and word not in ranks:
                ranks[word] = position
    return ranks


# ── Режим затравки ────────────────────────────────────────────────────────────

def parse_seed(path):
    entries, ranks = {}, {}
    with io.open(path, encoding="utf-8") as source:
        for line in source:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) != 5:
                print("  пропущена строка:", line)
                continue
            lemma, english, gloss, pos, rank = parts
            entries[lemma] = {"english": english, "gloss": gloss,
                              "pos": pos, "ambiguous": 0}
            ranks[lemma] = int(rank)
    return entries, ranks


# ── Запись ────────────────────────────────────────────────────────────────────

def write_database(path, entries, ranks, overrides, source_note):
    if os.path.exists(path):
        os.remove(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)

    connection = sqlite3.connect(path)
    connection.executescript(SCHEMA)
    connection.executemany(
        "INSERT INTO entries (lemma, english, gloss, pos, ambiguous) VALUES (?,?,?,?,?)",
        [(lemma, e["english"], e["gloss"], e["pos"], e["ambiguous"])
         for lemma, e in entries.items()])
    connection.executemany("INSERT INTO frequency (lemma, rank) VALUES (?,?)",
                           list(ranks.items()))
    # Слово, у которого есть собственная статья, переписывать нельзя.
    # Иначе «воздух» уезжает в «воздуха» (жаргонное «воздушная тревога»)
    # и читатель видит «Air raid siren был холодный». Таких коллизий
    # в машинном разборе Викисловаря тысячи.
    connection.executemany("INSERT INTO lemma_overrides (form, lemma) VALUES (?,?)",
                           [(form, lemma) for form, lemma in overrides.items()
                            if lemma in entries and form not in entries])
    connection.executemany("INSERT INTO meta (key, value) VALUES (?,?)", [
        ("source", source_note),
        ("license", "CC BY-SA 4.0 (Wiktionary), MIT (FrequencyWords)"),
        ("direction", "ru-en"),
    ])
    connection.commit()
    connection.execute("VACUUM")
    connection.close()


# ── Точка входа ───────────────────────────────────────────────────────────────

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description="Сборка словаря RU→EN в SQLite")
    parser.add_argument("--out", default=os.path.join(root, "Data", "ru-en.sqlite"))
    parser.add_argument("--sample", action="store_true",
                        help="собрать из tools/seed_ru_en.txt, без сети")
    parser.add_argument("--limit", type=int, default=None,
                        help="взять только N лемм — для быстрой проверки")
    args = parser.parse_args()

    if args.sample:
        print("Режим затравки — 120 слов, без сети.")
        entries, ranks = parse_seed(os.path.join(root, "tools", "seed_ru_en.txt"))
        overrides = {}
        note = "seed_ru_en.txt"
    else:
        cache = os.path.join(root, "Data", "cache")
        print("Шаг 1 из 3: Викисловарь")
        wiktionary = download(WIKTIONARY_URL, os.path.join(cache, "ru-wiktionary.jsonl"))
        print("Шаг 2 из 3: частотный список")
        frequency = download(FREQUENCY_URL, os.path.join(cache, "ru-frequency.txt"))
        print("Шаг 3 из 3: разбор")
        entries, overrides = parse_wiktionary(wiktionary, args.limit)
        ranks = parse_frequency(frequency, set(entries))
        note = "kaikki.org Russian Wiktionary + hermitdave/FrequencyWords"

    write_database(args.out, entries, ranks, overrides, note)

    size = os.path.getsize(args.out) / 1e6
    print()
    print("Готово:", args.out, "(%.1f МБ)" % size)
    print("  лемм:", len(entries))
    print("  с частотностью:", len(ranks))
    print("  исключений лемматизации:", len(overrides))
    print("  многозначных (не переводятся):",
          sum(1 for e in entries.values() if e["ambiguous"]))
    print()
    print("Проверить руками:")
    print('  sqlite3 %s "SELECT * FROM entries WHERE lemma=\'кровать\';"' % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
