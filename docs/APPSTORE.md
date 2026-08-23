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

### 3. App Store Connect — по шагам

Всё делается на <https://appstoreconnect.apple.com> под тем же Apple ID,
которым подписан сертификат команды `78LF5PH522`. Apple время от времени
переставляет разделы местами; ориентируйтесь на названия полей, они не меняются.

#### 3.1. Завести запись приложения

**Apps → синий «+» → New App.** В окне:

| Поле | Что ставить |
|---|---|
| Platforms | iOS |
| Name | `Десятое слово: учим английский` |
| Primary Language | Russian |
| Bundle ID | `com.tenthword.app` — выбрать из списка, он там уже есть |
| SKU | `TENTHWORD001` — внутренний код, покупателям не виден |
| User Access | Full Access |

Кнопка **Create**. С этой секунды имя занято за вами.

#### 3.2. Добавить английскую локализацию карточки

Слева **App Information**. Вверху справа выпадающий список языков →
**Add Language → English (U.K.)**. Заполнить `Name` и `Subtitle`
из раздела 4 ниже. Там же, на этой странице:

- **Category**: Primary — Books, Secondary — Education;
- **Copyright**: `2026 Yuri Koteniatkin` — обязательное поле, знак © Apple
  подставляет сама. Это не ссылка: год и владелец прав;
- **Content Rights**: приложение не содержит стороннего контента;
- **Age Rating → Edit**: на все вопросы анкеты «None» / «No», получится **4+**;
- **License Agreement**: не трогать. По умолчанию действует стандартный
  договор Apple, он подходит. `docs/terms.html` его не заменяет и не должен:
  собственный EULA вписывается туда текстом, а не ссылкой, и нужен только
  при особых условиях.

#### 3.3. Цена приложения

**Pricing and Availability**: цена приложения — **Free**. Деньги берутся
покупкой внутри, а не за скачивание. Availability — все страны.

#### 3.4. Завести покупку

Слева **Monetization → In-App Purchases → «+»** (в старом интерфейсе —
Features → In-App Purchases):

| Поле | Значение |
|---|---|
| Type | Non-Consumable |
| Reference Name | Полный доступ |
| Product ID | `com.tenthword.premium` — **обязан совпасть** с `PurchaseStore.premiumProductID` |
| Price | уровень **£4.99** (GBP 4.99) |

Дальше внутри товара: **Localizations → Russian** — Display Name «Полный доступ»,
Description «Снимает ограничение в десять страниц в день. Разовая покупка, не подписка.»
Добавить English (U.K.) — «Full access» и перевод описания.

**Review Information → Screenshot** пока оставить пустым. Это поле требует
картинку с пейволлом, а пейволл показывает цену только тогда, когда товар
уже существует в App Store Connect и приложение смогло его загрузить.
Снять такой скриншот в симуляторе нельзя: там нет ни товара, ни цены,
и кнопка честно пишет «Узнать цену».

Правильный порядок — снять его после загрузки сборки, в шаге 3.5.1.
Товар можно сохранить и без скриншота; заполнить поле нужно до отправки
на ревью, иначе заявку завернут.

#### 3.5. Загрузить сборку

Скачать **Transporter** из Mac App Store, войти тем же Apple ID,
перетащить `build/export/TenthWord.ipa` и нажать **Deliver**.
Обработка занимает от пятнадцати минут до часа; готовую сборку видно
в **TestFlight → iOS Builds**.

Если Apple пришлёт письмо про Export Compliance — отвечать не нужно,
`ITSAppUsesNonExemptEncryption = false` уже в Info.plist.

#### 3.5.1. Снять скриншот пейволла для покупки

Как только сборка обработалась, поставить её себе на iPhone через **TestFlight**.
Товар к этому моменту уже заведён (шаг 3.4), поэтому приложение получит от
App Store настоящую цену.

В приложении: **Настройки → Купить полный доступ**. Открывшийся пейволл покажет
кнопку «Купить за 4,99 £» вместо «Узнать цену». Снять скриншот кнопками
громкости и боковой, скинуть на Mac и приложить в **In-App Purchases →
com.tenthword.premium → Review Information → Screenshot**.

Заодно это и есть проверка покупки: нажать кнопку и пройти оплату
песочным Apple ID (**Настройки iOS → App Store → Sandbox Account**).
Деньги не списываются. Так закрываются два пункта из раздела 6.

#### 3.6. Заполнить страницу версии 1.0

Слева **iOS App → 1.0 Prepare for Submission**:

- **Screenshots**: перетащить пять файлов из `design/screenshots/`
  в слот **6.9" Display**. Остальные размеры Apple достроит сама.
  Пейволла среди них нет намеренно: скриншоты витрины показывают, чем
  приложение полезно, а не как оно просит денег. Для покупки нужен
  отдельный скриншот, см. шаг 3.5.1;
- **Description**, **Keywords**, **Promotional Text** — из раздела 4;
- **Support URL**: `https://yungqiuk.github.io/tenthword/support.html`;
- **Marketing URL**: `https://yungqiuk.github.io/tenthword/` — необязательное
  поле, но с ним на странице приложения появится ссылка «Сайт разработчика».
  Обязательных ссылок только две: Privacy Policy URL и Support URL;
- **Build**: нажать «+» и выбрать загруженную сборку;
- **In-App Purchases**: добавить `com.tenthword.premium` — это ключевой шаг,
  без него товар останется неодобренным, а покупка в релизе не заработает;
- **App Review Information**: демо-аккаунт не нужен, в Notes написать,
  что книги пользователь добавляет сам, и приложить пример файла;
- **Version Release**: «Automatically release this version».

#### 3.7. Анкета приватности

Слева **App Privacy → Get Started**. На первый вопрос ответ
**«No, we do not collect data from this app»** — и анкета кончается.
Это правда: ни аналитики, ни трекеров, манифест `PrivacyInfo.xcprivacy`
говорит то же самое.

#### 3.8. Отправить

Кнопка **Add for Review** вверху страницы версии, затем **Submit to App Review**.
Проверить, что в заявку попали и сборка, и покупка. Первое ревью — 1–3 дня,
изредка до недели.

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
| Название | `Десятое слово: учим английский` | 30 из 30 |
| Подзаголовок | `Читаете книгу — учите слова` | 27 из 30 |

Промотекст (170 знаков; меняется без новой сборки — годится для акций):

```
Начните с 5% — одно слово из двадцати. Дальше решаете вы: кольцо крутится до ста. Свои книги, полностью офлайн, без рекламы. Три дня бесплатно.
```

Ключевые слова (100 знаков, через запятую, **без пробелов после запятых** —
пробел съедает знак). Слов «десятое», «слово» и «английский» здесь нет
намеренно: они уже в названии, а повторы Apple не засчитывает дважды:

```
чтение,книги,словарь,перевод,epub,fb2,изучение,язык,читалка,офлайн,контекст,лексика,билингва
```

#### Английская локализация

| Поле | Значение | Знаков |
|---|---|---|
| Название | `Tenth Word: Learn English` | 25 из 30 |
| Подзаголовок | `English inside Russian books` | 28 из 30 |

Промотекст:

```
Start at 5% — one word in twenty. You decide the rest: the ring turns all the way to a hundred. Your own books, fully offline, no ads. Three days free.
```

Ключевые слова (`english` и `learn` убраны — они в названии):

```
russian,reading,books,vocabulary,dictionary,epub,fb2,offline,context,reader,bilingual,immersion
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

- [ ] Покупка проходит в песочнице и снимает лимит (шаг 3.5.1)
- [ ] У покупки заполнен Review Information → Screenshot
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
- **Интерфейса на английском не будет вообще.** Не отложен — не нужен:
  приложение продаётся тем, кто английский учит, а не тем, кто на нём говорит.
  Язык интерфейса всегда совпадает с языком книг, см. `docs/ROADMAP.md`.
  Карточка в App Store при этом двуязычная — так приложение находят те,
  у кого система переключена на английский.
- **CloudKit.** Третий слой защиты триала (`docs/TRIAL.md`) требует
  платного аккаунта и контейнера; первые два слоя работают без него.
