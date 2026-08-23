# Подача в App Store

Что уже сделано в репозитории и что придётся сделать руками в аккаунте Apple.
Порядок сверху вниз — это и есть порядок работы.

## Готово в проекте

| Требование Apple | Где лежит |
|---|---|
| Иконка 1024×1024, без прозрачности и скруглений | `App/TenthWord/Assets.xcassets/AppIcon.appiconset`, рисуется `swift tools/make_icon.swift` |
| Экран запуска | `UILaunchScreen` в `App/project.yml`, цвет `LaunchBackground` |
| Манифест конфиденциальности (обязателен с 2024 года) | `App/TenthWord/PrivacyInfo.xcprivacy` — данные не собираются, трекинга нет, объявлено использование `UserDefaults` с причиной `CA92.1` |
| Экспортное соответствие | `ITSAppUsesNonExemptEncryption = false` — вопрос про шифрование больше не задаётся на каждой сборке |
| Восстановление покупки | Пейволл и «Настройки → О программе» |
| Атрибуция CC BY-SA для словаря | «Настройки → О программе», плюс `docs/terms.html` |
| Ссылки на политику и поддержку внутри приложения | `AppLinks` в `App/TenthWord/Views/SettingsView.swift` |
| Страницы политики, поддержки и условий | `docs/index.html`, `privacy.html`, `support.html`, `terms.html` |
| Скриншоты 6.9″ (1320×2868) | `design/screenshots/` — сняты с симулятора iPhone 17 Pro Max |
| Товар для покупки | `App/TenthWord.storekit`, идентификатор `com.tenthword.premium` |
| Типы документов EPUB/FB2/TXT | `CFBundleDocumentTypes` в `App/project.yml` |
| Только iPhone | `TARGETED_DEVICE_FAMILY = 1` — iPad заявим позже, вместе с вёрсткой в две колонки |
| Страницы политики и поддержки опубликованы | <https://yungqiuk.github.io/tenthword/> — GitHub Pages из папки `/docs` |
| Подписанный архив для загрузки | `build/export/TenthWord.ipa`, `Apple Distribution (78LF5PH522)` |

## Что нужно сделать руками

### 1. Страницы политики — опубликованы

Репозиторий: <https://github.com/yungqiuk/tenthword>, страницы отдаёт GitHub Pages
из папки `/docs`. Все четыре адреса проверены и отвечают 200:

| Адрес | Куда идёт в App Store Connect |
|---|---|
| <https://yungqiuk.github.io/tenthword/> | Marketing URL (необязательно) |
| <https://yungqiuk.github.io/tenthword/privacy.html> | **Privacy Policy URL** |
| <https://yungqiuk.github.io/tenthword/support.html> | **Support URL** |
| <https://yungqiuk.github.io/tenthword/terms.html> | EULA (стандартный EULA Apple подходит) |

Почта поддержки — `yungqifr@gmail.com`, указана на странице поддержки
и должна совпадать с полем Support в App Store Connect.

Те же ссылки зашиты в приложение: `AppLinks` в
`App/TenthWord/Views/SettingsView.swift`. Меняется адрес — меняется и там.

### 2. Подпись — настроена

`App/project.yml`: команда `78LF5PH522`, автоматическая подпись.
`CODE_SIGN_IDENTITY` руками не задаётся — при автоматической подписи
это конфликт, сборка падает с «conflicting provisioning settings».

Bundle ID `com.tenthword.app` зарегистрирован в аккаунте разработчика
автоматически, при первом архиве с `-allowProvisioningUpdates`.

### 3. App Store Connect

Создать приложение (Bundle ID из предыдущего шага) и заполнить:

- **In-App Purchase**: тип Non-Consumable, Product ID **`com.tenthword.premium`**
  (обязан совпадать с `PurchaseStore.premiumProductID`), цена — уровень £4.99,
  название «Полный доступ». Товар подаётся на ревью вместе с первой сборкой.
- **Privacy Policy URL** и **Support URL** — адреса из шага 1.
- **App Privacy**: «Data Not Collected». Это правда: ни аналитики, ни трекеров.
- **Age Rating**: 4+. Пользовательского контента и внешних ссылок на него нет.
- **Category**: Books, вторая — Education.

### 4. Названия и тексты для карточки

Одно приложение — две локализации карточки. Название и подзаголовок задаются
**отдельно для каждого языка** в App Store Connect: App Information →
Localizable Information. Основной язык — русский, вторая локализация —
English (U.K.). Заводить два приложения не нужно и нельзя.

Оба названия проверены поиском по каталогу и на август 2026 года свободны.
Окончательную проверку делает сам App Store Connect в момент регистрации:
имя может быть зарезервировано кем-то и не выпущено, из каталога этого не видно.
**Занимать имя стоит сразу** — для этого достаточно создать запись приложения,
сборка не требуется. Незанятое сборкой имя Apple освобождает через 180 дней,
так что затягивать с первой загрузкой не стоит.

#### Русская локализация

| Поле | Значение | Знаков |
|---|---|---|
| Название | `Десятое слово: английский` | 25 из 30 |
| Подзаголовок | `Читаете книгу — учите слова` | 27 из 30 |

Ключевые слова (100 знаков, через запятую, без пробелов):

```
английский,чтение,книги,словарь,перевод,epub,fb2,изучение,язык,читалка,офлайн,контекст
```

#### Английская локализация

| Поле | Значение | Знаков |
|---|---|---|
| Название | `Tenth Word: Learn English` | 25 из 30 |
| Подзаголовок | `English inside Russian books` | 28 из 30 |

Ключевые слова:

```
russian,english,reading,books,vocabulary,dictionary,epub,fb2,offline,context,learn,reader
```

#### Описание (русское)

```
Вы открываете русскую книгу — и часть слов в ней уже английские.
Сколько именно, решаете вы: кольцо крутится от 0 до 100%.

На 10% английское каждое десятое слово — отсюда и название.
Читается почти как обычная книга, но каждый абзац подсовывает вам
новое английское слово в контексте, где смысл понятен и без словаря.
Мозг достраивает сам — так язык и запоминается. Не достроил —
тап по слову покажет перевод.

Слово, которое вы выучили, можно убрать: освободившийся процент
займёт следующее.

— Свои книги: EPUB, FB2, TXT
— Полностью офлайн: словарь внутри приложения
— Порядок слов не перетасовывается, когда вы меняете процент
— Имена собственные и многозначные слова не переводятся
— Темы, шрифты, размер, межстрочный интервал
— Никакой рекламы и никакого сбора данных

Три дня бесплатно. Потом десять страниц в день бесплатно
или разовая покупка — не подписка.
```

#### Описание (английское)

```
Open a Russian book and some of the words are already English.
How many is up to you: the ring turns from 0 to 100%.

At 10% every tenth word is English — hence the name. It still reads
like an ordinary book, but every paragraph hands you a new English
word in a context where the meaning is obvious without a dictionary.
Your brain fills in the rest — that is how vocabulary sticks.
If it does not, tap the word to see what it replaced.

Learned a word? Remove it, and the freed percent goes to the next one.

— Your own books: EPUB, FB2, TXT
— Fully offline: the dictionary lives inside the app
— Word order never reshuffles when you change the percentage
— Proper nouns and ambiguous words are never translated
— Themes, typefaces, size, line spacing
— No ads, no data collection

Three days free. Then ten pages a day free, or a one-time purchase —
not a subscription.
```

**Что нового** (для версии 1.0): `Первая версия.` / `First release.`

#### Что ещё стоит занять под это имя

- домен **tenthword.com** — свободен (на 21 августа 2026); `tenthword.io`
  и `desyatoeslovo.com` тоже свободны, `tenthword.app` занят;
- имя репозитория на GitHub — от него зависит адрес страниц политики;
- товарный знак проверять по базе UK IPO — этого из терминала не сделать.

### 5. Сборка и загрузка

Архив и `.ipa` собираются одной парой команд, без Xcode:

```bash
cd App && xcodegen generate && xcodebuild -project TenthWord.xcodeproj -scheme TenthWord -configuration Release -destination 'generic/platform=iOS' -archivePath ../build/TenthWord.xcarchive -allowProvisioningUpdates archive
```

```bash
xcodebuild -exportArchive -archivePath build/TenthWord.xcarchive -exportOptionsPlist build/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

Получается `build/export/TenthWord.ipa`, 12 МБ, подписан
`Apple Distribution: YURI KOTENIATKIN (78LF5PH522)`, `get-task-allow = false`.
Это готовый к загрузке файл.

Загрузить его можно тремя способами: приложением **Transporter** из Mac App Store
(перетащить `.ipa`), из Xcode через Organizer, или командой `xcrun altool
--upload-app`, для которой нужен пароль приложения или ключ App Store Connect API.
Загрузка сработает только после того, как в App Store Connect создана запись
приложения с тем же Bundle ID.

### 6. Перед отправкой на ревью — проверить руками

- [ ] Покупка проходит в песочнице и снимает лимит
- [ ] «Восстановить покупку» возвращает доступ на чистом устройстве
- [ ] Обе ссылки (политика, поддержка) открываются с реального устройства
- [ ] Цена на пейволле — из App Store, а не «Узнать цену»: значит, товар одобрен
- [ ] Импорт проверен на пяти настоящих книгах: EPUB, FB2, TXT разного происхождения
- [ ] Триал показывает «осталось N дней» на первом запуске
- [ ] После триала лимит десять страниц в день действительно срабатывает

Про триал и лимит страниц проверено в симуляторе. Ссылки отвечают 200,
но с устройства их стоит открыть глазами. Остальное требует товара,
заведённого в App Store Connect.

## Чего в сборке сознательно нет

- **iPad.** Заявлять поддержку — значит показывать вёрстку в две колонки
  и готовить отдельные скриншоты. Отложено, см. `docs/ROADMAP.md`.
- **Локализация интерфейса на английский.** Интерфейс русский: первая версия
  для читателей, у которых русский родной. Карточка в App Store при этом
  двуязычная.
- **CloudKit.** Третий слой защиты триала (`docs/TRIAL.md`) требует
  платного аккаунта и контейнера; первые два слоя работают без него.
