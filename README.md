# Читалка — что делать на Mac

Папка перенесена с Windows. Здесь по шагам то, что нельзя было сделать без macOS.
Каждый шаг проверяемый: в конце написано, что должно получиться.

Общий контекст проекта — в [CLAUDE.md](CLAUDE.md). Открывайте Claude Code прямо в этой папке,
он прочитает CLAUDE.md сам.

---

## Шаг 0. Проверить, что есть

```bash
xcode-select -p        # должен вывести путь к Xcode, а не к CommandLineTools
swift --version        # 5.9 или новее
python3 --version      # 3.9 или новее
```

Если `xcode-select` показывает `/Library/Developer/CommandLineTools`, выполните
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

---

## Шаг 1. Собрать словарь

В папке уже лежит `Data/ru-en.sqlite` на 44 КБ — это **словарь-затравка**, 136 частых
слов. Он собран заранее, чтобы приложение можно было запустить сразу, не дожидаясь
большой загрузки. Пересобрать его — секунда, без сети:

```bash
python3 tools/build_dictionary.py --sample
```

Настоящий словарь собирается отдельно. Скрипт качает машинный разбор русского
Викисловаря с kaikki.org и раскладывает его в SQLite.

```bash
python3 -m pip install -r tools/requirements.txt
python3 tools/build_dictionary.py --out Data/ru-en.sqlite
```

Займёт 10–40 минут: качается ~1 ГБ JSONL, на выходе остаётся 10–20 МБ.
Промежуточный файл кладётся в `Data/cache/`, повторный запуск его переиспользует.

**Должно получиться:** `Data/ru-en.sqlite` на 10–20 МБ, и в конце вывода —
статистика вида `лемм: 118432, с переводом: 104120`.

Проверить руками:

```bash
sqlite3 Data/ru-en.sqlite "SELECT lemma, english, pos FROM entries WHERE lemma IN ('кровать','яблоко','блестеть');"
```

Лицензия данных — CC BY-SA. Атрибуция обязана быть на экране «О программе»,
заготовка текста лежит в [docs/DATA.md](docs/DATA.md).

---

## Шаг 2. Прогнать тесты логики

Это работает без Xcode-проекта и без симулятора.

```bash
cd Core
swift test
```

**Должно получиться:** все тесты зелёные. Главный из них — `testMonotonicity`:
он проверяет, что план перевода на 10% содержит в себе весь план на 5%.
Если он красный, кольцо будет перетасовывать текст под пальцем, и это надо чинить
до всего остального.

Второй важный — `testMatchesGoldenFixture`. Он сверяет Swift с эталоном
`Core/Tests/ReaderCoreTests/Fixtures/golden_plan.json`, который сгенерирован независимой
реализацией того же алгоритма на Python. Если он красный, Swift и Python разошлись:
почти наверняка в токенизаторе или в `StableHash`.

Код писался без компилятора. Синтаксические ошибки на этом шаге — норма, чините смело.

---

## Шаг 3. Собрать Xcode-проект

Проект собирается из описания `App/project.yml` утилитой XcodeGen. Сам `.xcodeproj` —
генерируемый XML, который конфликтует при любом слиянии, поэтому в репозитории его нет:
источник правды — `project.yml`.

```bash
brew install xcodegen
cd App && xcodegen generate
```

**Должно получиться:** `App/Chitalka.xcodeproj`. Открывается в Xcode, собирается (⌘B),
запускается в симуляторе. Локальный пакет `Core`, словарь `Data/ru-en.sqlite`
и зависимость ZIPFoundation уже прописаны в `project.yml` — руками подключать нечего.

Проверить сборку без Xcode:

```bash
cd App && xcodebuild -project Chitalka.xcodeproj -scheme Chitalka \
  -destination 'generic/platform=iOS Simulator' build
```

Если правите `project.yml` — перегенерируйте проект той же командой. Настройки,
внесённые мышью в Xcode, при следующей генерации потеряются.

## Шаг 4. Подписать и запустить на устройстве

Signing & Capabilities → Team: ваш аккаунт разработчика.
Bundle Identifier поменять на свой, например `com.вашеимя.chitalka`.

Для CloudKit (третий слой защиты триала, см. [docs/TRIAL.md](docs/TRIAL.md)):
+ Capability → iCloud → CloudKit, контейнер `iCloud.com.вашеимя.chitalka`.
Можно отложить: без него первые два слоя защиты работают.

---

## Шаг 5. Первое, что стоит увидеть глазами

Порядок, в котором приложение оживает:

1. `LibraryView` с шестью тестовыми книгами — проверить сетку и кольца
2. `PercentRing` — покрутить пальцем, поймать тактильную отдачу на каждых 5%
3. Импорт EPUB через Files — проверить на реальной книге
4. `ReaderView` с настоящим текстом и настоящим словарём

Дальше по [docs/ROADMAP.md](docs/ROADMAP.md).

---

## Карта папок

```
CLAUDE.md              контекст для Claude Code — читается автоматически
README.md              этот файл
docs/                  решения, архитектура, данные, защита триала, план
design/mockup.html     утверждённый дизайн; откройте в браузере, кольцо рабочее
Core/                  Swift Package: вся логика перевода, тестируется без Xcode
App/Chitalka/          SwiftUI-исходники, ждут Xcode-проекта
tools/                 Python: сборка словаря, генерация эталона для тестов
Data/                  собранный словарь; в git не коммитится
```
