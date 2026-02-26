# Roadmap: Разработка MQL5 EA (Milestone 2)

Этот документ описывает план реализации и тестирования советника (Expert Advisor) для MetaTrader 5, который взаимодействует с парсером сигналов Telegram.

## 1. Архитектура и структура проекта
- [ ] Соблюдение стандартов `mt5-coder.md`:
    - Использование только стандартной библиотеки (`CTrade`, `CPositionInfo`, `CSymbolInfo`).
    - Обязательная обработка ошибок для каждой торговой операции.
    - Строгая типизация и именование переменных на английском языке (префикс `Inp` для инпутов).
- [ ] Создание файловой структуры проекта:
    - `MQL5/Experts/TelegramSignalExpert.mq5` — Основной файл (входные параметры, события `OnInit`, `OnDeinit`, `OnTimer`).
    - `MQL5/Include/TelegramExpert/Defines.mqh` — Глобальные перечисления, структуры (SignalData) и макросы.
    - `MQL5/Include/TelegramExpert/Database.mqh` — Класс `CDatabaseManager` для работы с SQLite (чистый MQL5 API).
    - `MQL5/Include/TelegramExpert/RiskManager.mqh` — Класс `CRiskManager` (расчет лотов, JST время, Daily Loss мониторинг).
    - `MQL5/Include/TelegramExpert/TradeEngine.mqh` — Класс `CTradeEngine` (открытие ордеров, закрытие по сигналу, логика БУ).
    - `MQL5/Include/TelegramExpert/SignalManager.mqh` — Класс `CSignalManager` (высокоуровневая координация: "Мозг" советника).

## 2. Проектирование Базовых Компонентов (Defines.mqh)
- [ ] Определение `enum ENUM_SIGNAL_STATUS` (PROCESS, MODIFY, DONE, ERROR).
- [ ] Определение `struct SSignalData` для хранения всех параметров сигнала из БД.
- [ ] Определение констант: `MAX_ENTRY_DEVIATION = 0.03`, `JST_OFFSET = 32400` (9 часов).

## 3. Ядро обработки данных (Database.mqh)
- [ ] Реализация класса `CDatabaseManager`:
    - Метод `Open(string path)`: Открытие БД с флагами доступа.
    - Метод `GetNewSignals(SSignalData &signals[])`: Запрос записей `PROCESS`/`MODIFY`.
    - Метод `SetSignalDone(int id)`: Обновление статуса в БД.
- [ ] SQL-запросы с использованием параметров для безопасности.

## 4. Управление рисками и временем (RiskManager.mqh)
- [ ] Реализация класса `CRiskManager`:
    - Метод `IsTradingAllowed()`: Проверка 3% лимита и JST времени разблокировки.
    - Метод `CalculateLot(double entry, double sl)`: Динамический расчет с нормализацией.
    - Метод `SyncEquityReference()`: Фиксация эквити в 07:10 JST.

## 5. Торговый Движок и Логика (TradeEngine.mqh)
- [ ] Реализация класса `CTradeEngine`:
    - Использование `CTrade` для выполнения операций.
    - Метод `OpenDualPosition(SSignalData &signal)`: Открытие двух ордеров с разными TP.
    - Метод `ManageBreakeven()`: Перенос в БУ при достижении TP1.
    - Метод `CloseAll()`: Экстренное или плановое закрытие всех позиций.

## 6. Интеграция и Основной Цикл (SignalManager.mqh + .mq5)
- [ ] Реализация класса `CSignalManager`: связка БД -> Риски -> Торговля.
- [ ] Главный файл: Минималистичный `OnTimer` вызывающий `SignalManager.Tick()`.

## 4. Динамический расчет лота (Money Management)
- [ ] Реализация функции `CalculateLotSize(double sl_price)`:
    - Если `LotType == Fixed`: возврат `InpLotValue`.
    - Если `LotType == RiskPercent`:
        - Получение `Equity = AccountInfoDouble(ACCOUNT_EQUITY)`.
        - Расчет суммы риска: `RiskAmount = Equity * InpLotValue / 100.0`.
        - Расчет дистанции SL в пунктах: `PointsDist = MathAbs(Entry - sl_price) / Point`.
        - Расчет лота: `Lot = RiskAmount / (PointsDist * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE))`.
- [ ] Округление и нормализация лота под требования брокера (`SYMBOL_VOLUME_STEP`, `SYMBOL_VOLUME_MIN`).

## 5. Управление позициями (Trade Management)
- [ ] Мониторинг Order 1:
    - Обнаружение закрытия по TP1
- [ ] Логика Breakeven для Order 2:
    - Перенос SL в безубыток (цена входа) после срабатывания TP1
- [ ] Поддержка ручных изменений:
    - EA не должен перезаписывать ручные правки SL/TP, если они не противоречат основной логике

## 6. Управление временем и часовыми поясами (JST Logic)
- [ ] Реализация функции `GetJSTTime()`:
    - Использование `TimeGMT()` для получения независимого времени.
    - Добавление смещения +9 часов для получения текущего JST.
- [ ] Логика ежедневного сброса лимитов:
    - Определение целевого времени 07:10 JST в формате GMT (22:10 GMT).
    - Обработка перехода через полночь: если лимит превышен, блокировка ставится до ближайшего следующего 07:10 JST.
- [ ] Синхронизация с сервером:
    - Проверка `TimeTradeServer()` для корректного закрытия сделок перед выходными (если применимо), но основной контроль разблокировки — по GMT/JST.

## 7. Риск-менеджмент и безопасность
- [ ] Мониторинг эквити (Equity) в реальном времени:
    - Фиксация `g_starting_equity` в 07:10 JST каждого дня.
- [ ] Расчет Daily Loss:
    - Проверка условия: `(CurrentEquity - g_starting_equity) / g_starting_equity <= -0.03`.
- [ ] Принудительное действие:
    - Немедленное закрытие всех позиций и удаление ордеров при достижении -3%.
    - Установка флага `g_trading_locked = true`.
- [ ] Торговая блокировка:
    - Запрет на открытие новых позиций, если `g_trading_locked == true`.
    - Автоматический сброс флага при наступлении 07:10 JST следующего дня.

## 8. Техническое тестирование (QA)
- [ ] Тестирование временной логики:
    - Эмуляция достижения лимита потерь.
    - Проверка, что советник игнорирует сигналы до наступления 07:10 JST.
    - Проверка корректности пересчета GMT -> JST.

## 9. Финализация
- [ ] Оптимизация кода и логирования
- [ ] Подготовка финального .mq5 файла
