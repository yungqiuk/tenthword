#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генератор эталона для тестов ядра перевода.

Это независимая реализация того же алгоритма, что в Core/Sources/ReaderCore.
Смысл в том, что она независимая: если Swift и Python дают разный результат,
значит кто-то из них неправ, и тест `testMatchesGoldenFixture` это ловит.

Чаще всего расходятся две вещи:
  * токенизатор — правила разбора на слова разъехались между реализациями;
  * StableHash — не тот порядок байт или не то смещение битов.

Запуск:
    python3 tools/make_golden.py

Пишет Core/Tests/ReaderCoreTests/Fixtures/golden_plan.json.
Перегенерировать нужно только если сознательно менялся алгоритм отбора.
Если тест покраснел сам по себе — чинить надо код, а не эталон.
"""

import json
import math
import os
import sys

# ── Константы. Обязаны совпадать с TranslationEngine.swift ────────────────────

FREQUENCY_WEIGHT = 0.65
FREQUENCY_HORIZON = 20000.0

SENTENCE_ENDERS = set(".!?…")
WORD_JOINERS = set("-'’")


# ── StableHash: FNV-1a, 64 бита ───────────────────────────────────────────────

def fnv1a64(text):
    """Обязан совпадать с StableHash.fnv1a64 байт в байт."""
    h = 0xcbf29ce484222325
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def mix64(value):
    """Финализатор splitmix64. Обязан совпадать с StableHash.mix.

    FNV-1a сам по себе плохо разносит старшие биты на ключах вида `лемма#номер`,
    а джиттер в отборе устроен именно так. Без перемешивания переведённые слова
    сбиваются в кучу на странице.
    """
    x = value
    x ^= x >> 30
    x = (x * 0xbf58476d1ce4e5b9) & 0xFFFFFFFFFFFFFFFF
    x ^= x >> 27
    x = (x * 0x94d049bb133111eb) & 0xFFFFFFFFFFFFFFFF
    x ^= x >> 31
    return x


def unit_interval(text):
    """Старшие 53 бита перемешанного хеша в [0, 1). Столько значащих бит у double."""
    return float(mix64(fnv1a64(text)) >> 11) * (2.0 ** -53)


# ── Токенизатор. Правила см. в Tokenizer.swift ────────────────────────────────

def utf16_length(ch):
    return len(ch.encode("utf-16-le")) // 2


def tokenize(text):
    tokens = []
    buffer = []
    buffer_start = 0
    offset = 0
    ordinal = 0
    at_sentence_start = True
    chars = list(text)

    def flush():
        nonlocal buffer, ordinal, at_sentence_start
        if not buffer:
            return
        surface = "".join(buffer)
        tokens.append({
            "surface": surface,
            "utf16Offset": buffer_start,
            "utf16Length": offset - buffer_start,
            "ordinal": ordinal,
            "startsSentence": at_sentence_start,
        })
        ordinal += 1
        at_sentence_start = False
        buffer = []

    for i, ch in enumerate(chars):
        if ch.isalpha():
            if not buffer:
                buffer_start = offset
            buffer.append(ch)
        elif ch in WORD_JOINERS and buffer and i + 1 < len(chars) and chars[i + 1].isalpha():
            buffer.append(ch)
        else:
            flush()
            if ch in SENTENCE_ENDERS:
                at_sentence_start = True
        offset += utf16_length(ch)
    flush()

    return tokens


# ── Отбор кандидатов. См. TranslationEngine.prepare ───────────────────────────

CONTENT_POS = {"noun", "verb", "adjective", "adverb"}


def looks_like_proper_noun(token):
    return token["surface"][:1].isupper() and not token["startsSentence"]


# Обязан совпадать с FunctionWords.ambiguousPronounForms в Core.
AMBIGUOUS_PRONOUN_FORMS = {
    "том", "тем", "той", "тому", "тою", "те", "теми",
    "этом", "этим", "этими", "эти",
    "нём", "нем", "ней", "неё", "нему", "ним", "ними", "них",
    "мой", "моей", "три", "стать", "пора",
}


def build_candidates(tokens, lemmas, dictionary, ranks, function_words, learned):
    candidates = []
    for i, token in enumerate(tokens):
        lemma = lemmas[i]

        if looks_like_proper_noun(token):
            continue
        # Формы местоимений, которые лемматизатор путает с существительными.
        if (token["surface"].lower() in AMBIGUOUS_PRONOUN_FORMS
                or lemma in AMBIGUOUS_PRONOUN_FORMS):
            continue
        entry = dictionary.get(lemma)
        if entry is None:
            continue
        if entry.get("ambiguous"):
            continue
        if lemma in learned:
            continue

        pos = entry.get("pos", "other")
        is_function = lemma in function_words or pos not in CONTENT_POS

        rank = ranks.get(lemma)
        frequency = min(float(rank) / FREQUENCY_HORIZON, 1.0) if rank is not None else 0.5
        jitter = unit_interval("%s#%d" % (lemma, token["ordinal"]))
        weight = FREQUENCY_WEIGHT * frequency + (1 - FREQUENCY_WEIGHT) * jitter

        candidates.append({
            "ordinal": token["ordinal"],
            "surface": token["surface"],
            "lemma": lemma,
            "english": entry["english"],
            "pos": pos,
            "isFunctionWord": is_function,
            "weight": weight,
        })

    # Ярус, потом вес, потом порядок в тексте. Последний ключ делает сортировку
    # полной: без него Swift и Python могли бы разойтись на равных весах,
    # потому что сортировка в Swift нестабильна.
    candidates.sort(key=lambda c: (c["isFunctionWord"], c["weight"], c["ordinal"]))
    return candidates


def plan(candidates, total_words, percent):
    # Swift .rounded() округляет половину от нуля, а питоновский round() —
    # к чётному. Здесь нужен первый вариант.
    target = int(math.floor(percent / 100.0 * total_words + 0.5))
    target = max(0, min(target, len(candidates)))
    return [c["ordinal"] for c in candidates[:target]]


# ── Данные эталона ────────────────────────────────────────────────────────────

TEXT = (
    "Сегодня утром я встал с кровати, чтобы пойти в сад за яблоками. "
    "Воздух был холодный, и трава ещё блестела от росы. "
    "Соседская собака бежала вдоль забора и лаяла на птиц. "
    "Я поднял корзину, открыл старую калитку и медленно пошёл по тропинке "
    "между деревьями. Небо становилось светлее, где-то далеко звонил колокол, "
    "и день казался длинным и спокойным. У калитки меня ждал Пётр."
)

# словоформа → лемма
LEMMAS = {
    "утром": "утро", "встал": "встать", "кровати": "кровать", "пойти": "пойти",
    "сад": "сад", "яблоками": "яблоко", "воздух": "воздух", "был": "быть",
    "холодный": "холодный", "трава": "трава", "блестела": "блестеть", "росы": "роса",
    "соседская": "соседский", "собака": "собака", "бежала": "бежать", "забора": "забор",
    "лаяла": "лаять", "птиц": "птица", "поднял": "поднять", "корзину": "корзина",
    "открыл": "открыть", "старую": "старый", "калитку": "калитка", "калитки": "калитка",
    "медленно": "медленно", "пошёл": "пойти", "тропинке": "тропинка",
    "деревьями": "дерево", "небо": "небо", "становилось": "становиться",
    "светлее": "светлый", "далеко": "далеко", "звонил": "звонить", "колокол": "колокол",
    "день": "день", "казался": "казаться", "длинным": "длинный", "спокойным": "спокойный",
    "меня": "я", "ждал": "ждать", "пётр": "пётр",
}

# лемма → статья. rank — ранг частотности, 1 = самое частое слово языка.
ENTRIES = {
    "утро":       {"english": "morning",   "pos": "noun",        "rank": 620},
    "встать":     {"english": "get up",    "pos": "verb",        "rank": 810},
    "кровать":    {"english": "bed",       "pos": "noun",        "rank": 1450},
    "пойти":      {"english": "go",        "pos": "verb",        "rank": 240},
    "сад":        {"english": "garden",    "pos": "noun",        "rank": 1980},
    "яблоко":     {"english": "apple",     "pos": "noun",        "rank": 4300},
    "воздух":     {"english": "air",       "pos": "noun",        "rank": 1120},
    "холодный":   {"english": "cold",      "pos": "adjective",   "rank": 1670},
    "трава":      {"english": "grass",     "pos": "noun",        "rank": 2900},
    "блестеть":   {"english": "glisten",   "pos": "verb",        "rank": 7400},
    "роса":       {"english": "dew",       "pos": "noun",        "rank": 12800},
    "соседский":  {"english": "neighbour's", "pos": "adjective", "rank": 9100},
    "собака":     {"english": "dog",       "pos": "noun",        "rank": 1530},
    "бежать":     {"english": "run",       "pos": "verb",        "rank": 1340},
    "забор":      {"english": "fence",     "pos": "noun",        "rank": 5200},
    "лаять":      {"english": "bark",      "pos": "verb",        "rank": 11200},
    "птица":      {"english": "bird",      "pos": "noun",        "rank": 1890},
    "поднять":    {"english": "pick up",   "pos": "verb",        "rank": 700},
    "корзина":    {"english": "basket",    "pos": "noun",        "rank": 6100},
    "открыть":    {"english": "open",      "pos": "verb",        "rank": 390},
    "старый":     {"english": "old",       "pos": "adjective",   "rank": 310},
    "калитка":    {"english": "gate",      "pos": "noun",        "rank": 8700},
    "медленно":   {"english": "slowly",    "pos": "adverb",      "rank": 2100},
    "тропинка":   {"english": "path",      "pos": "noun",        "rank": 7900},
    "дерево":     {"english": "tree",      "pos": "noun",        "rank": 1290},
    "небо":       {"english": "sky",       "pos": "noun",        "rank": 1060},
    "светлый":    {"english": "bright",    "pos": "adjective",   "rank": 2450},
    "далеко":     {"english": "far away",  "pos": "adverb",      "rank": 1210},
    "звонить":    {"english": "ring",      "pos": "verb",        "rank": 3300},
    "колокол":    {"english": "bell",      "pos": "noun",        "rank": 9800},
    "день":       {"english": "day",       "pos": "noun",        "rank": 180},
    "длинный":    {"english": "long",      "pos": "adjective",   "rank": 1750},
    "спокойный":  {"english": "calm",      "pos": "adjective",   "rank": 3100},
    "ждать":      {"english": "wait",      "pos": "verb",        "rank": 560},
    # многозначное: key или spring — без контекста выберем неверно, поэтому не трогаем
    "ключ":       {"english": "key",       "pos": "noun",        "rank": 2600, "ambiguous": True},
    # служебные — последний ярус
    "я":          {"english": "I",         "pos": "pronoun",     "rank": 12},
    "с":          {"english": "with",      "pos": "preposition", "rank": 21},
    "в":          {"english": "in",        "pos": "preposition", "rank": 3},
    "за":         {"english": "behind",    "pos": "preposition", "rank": 48},
    "и":          {"english": "and",       "pos": "conjunction", "rank": 2},
    "от":         {"english": "from",      "pos": "preposition", "rank": 74},
    "вдоль":      {"english": "along",     "pos": "preposition", "rank": 1900},
    "на":         {"english": "on",        "pos": "preposition", "rank": 6},
    "по":         {"english": "along",     "pos": "preposition", "rank": 31},
    "между":      {"english": "between",   "pos": "preposition", "rank": 420},
    "у":          {"english": "at",        "pos": "preposition", "rank": 55},
    "чтобы":      {"english": "in order to", "pos": "conjunction", "rank": 96},
    "быть":       {"english": "be",        "pos": "verb",        "rank": 8},
    "становиться": {"english": "become",   "pos": "verb",        "rank": 340},
    "казаться":   {"english": "seem",      "pos": "verb",        "rank": 470},
}

# Служебные леммы. Подмножество FunctionWords.all, которого хватает этому тексту.
FUNCTION_WORDS = {
    "я", "с", "в", "за", "и", "от", "вдоль", "на", "по", "между", "у", "чтобы",
    "быть", "становиться", "казаться", "ещё", "где-то",
}

LEARNED = set()

PERCENTS = [0, 1, 5, 10, 12, 25, 40, 55, 60, 75, 90, 100]


def main():
    # Консоль Windows по умолчанию не в UTF-8, а выводим мы кириллицу.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_path = os.path.join(root, "Core", "Tests", "ReaderCoreTests",
                            "Fixtures", "golden_plan.json")

    tokens = tokenize(TEXT)
    lemmas = [LEMMAS.get(t["surface"].lower(), t["surface"].lower()) for t in tokens]
    candidates = build_candidates(tokens, lemmas, ENTRIES,
                                  {k: v["rank"] for k, v in ENTRIES.items() if "rank" in v},
                                  FUNCTION_WORDS, LEARNED)

    fixture = {
        "_comment": "Сгенерировано tools/make_golden.py. Руками не править.",
        "text": TEXT,
        "lemmas": LEMMAS,
        "entries": ENTRIES,
        "functionWords": sorted(FUNCTION_WORDS),
        "learned": sorted(LEARNED),
        "totalWords": len(tokens),
        "tokens": tokens,
        "order": [c["ordinal"] for c in candidates],
        "plans": {str(p): plan(candidates, len(tokens), p) for p in PERCENTS},
    }

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(fixture, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write("\n")

    print("Записано:", out_path)
    print("Слов всего:", len(tokens))
    print("Кандидатов:", len(candidates),
          "(из них служебных: %d)" % sum(1 for c in candidates if c["isFunctionWord"]))
    print("Не переводится:", len(tokens) - len(candidates))
    print()
    print("Первые десять по очереди:")
    for c in candidates[:10]:
        print("   %-14s → %-12s вес %.6f" % (c["surface"], c["english"], c["weight"]))
    print()
    print("Текст на 12%:")
    chosen = set(plan(candidates, len(tokens), 12))
    by_ordinal = {c["ordinal"]: c for c in candidates}
    words = []
    for t in tokens:
        if t["ordinal"] in chosen:
            english = by_ordinal[t["ordinal"]]["english"]
            if t["surface"][:1].isupper():
                english = english[:1].upper() + english[1:]
            words.append(english)
        else:
            words.append(t["surface"])
    print("   " + " ".join(words))
    return 0


if __name__ == "__main__":
    sys.exit(main())
