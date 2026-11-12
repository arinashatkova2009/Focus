import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import QtMultimedia
import QtQuick.Dialogs
import focus

ApplicationWindow {
    id: win
    width: Math.min(1400, Screen.desktopAvailableWidth); height: Math.min(740, Screen.desktopAvailableHeight)
    minimumWidth: Math.min(1180, Screen.desktopAvailableWidth); minimumHeight: Math.min(680, Screen.desktopAvailableHeight)
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Focus — ваш AI-помощник"
    color: bg
    font.family: "Segoe UI"
    font.pixelSize: 14
    readonly property color bg: backend.dark ? "#181b22" : "#e9e6e7"
    readonly property color surface: backend.dark ? "#222630" : "#ffffff"
    readonly property color ink: backend.dark ? "#f5f2ee" : "#282728"
    readonly property color muted: backend.dark ? "#b1afad" : "#7b777d"
    readonly property color line: backend.dark ? "#393c45" : "#dedadd"
    readonly property color accent: backend.dark ? "#9a93a5" : "#5b5560"
    readonly property color soft: backend.dark ? "#2d2c33" : "#efecee"
    readonly property color glass: backend.dark ? "#1fffffff" : "#8cffffff"
    readonly property color glassSoft: backend.dark ? "#14ffffff" : "#66ffffff"
    readonly property color glassEdge: backend.dark ? "#33ffffff" : "#e6ffffff"
    readonly property color fieldEdge: backend.dark ? "#40ffffff" : "#2a8a6a50"
    readonly property string heroFont: "Segoe UI"
    property bool loggedIn: false
    property string userName: ""
    property string page: "home"
    property string agent: "eva"
    property bool chatOpen: false
    property bool chatBusy: false
    property bool chatRecording: false
    property string chatAudioUrl: ""
    property bool loginBusy: false
    property string authMode: "welcome"
    readonly property bool authVisible: !loggedIn
    readonly property string uiFont: fontMedium.name !== "" ? fontMedium.name : "Segoe UI"
    readonly property string displayFont: fontDisplay.name !== "" ? fontDisplay.name : "Segoe UI Black"
    property string userRole: ""
    property var utilityRecords: []
    property string utilityTitle: ""
    property string utilityError: ""

    property bool loading: false
    property string loginError: ""
    property string pageError: ""
    property string notice: ""
    property var records: []
    property var metrics: []
    property var folders: []
    property int selectedFolderId: -1
    property string documentSearchText: ""
    property bool folderBusy: false
    property bool documentBusy: false
    property var pinnedFeatures: ["", "", "", ""]
    property int pinSlotToFill: -1
    property string hoverAgent: ""
    property string homeAttachedFileUrl: ""
    property string homeAttachedFileName: ""
    property string homeQueryText: ""
    property bool homeSearchBusy: false
    property bool calendarCollapsed: false
    property var history: []
    property var callbacks: ({})
    property int sessionEpoch: 0
    property int pageRequest: 0
    property var seenIntros: ({})
    readonly property var agents: [
        { key:"eva", name:"Eva", area:"Коммуникации", description:"Разбирает почту и рабочие переписки, помогает готовить точные ответы.", tint:"#fae8db", image:"agent-eva.png", portrait:0 },
        { key:"leo", name:"Leo", area:"Команда", description:"Следит за поручениями, сроками и статусами команды.", tint:"#e9eddf", image:"agent-leo.png", portrait:1 },
        { key:"nick", name:"Nick", area:"Встречи", description:"Планирует встречи, повестки и рабочие протоколы.", tint:"#e5ebf1", image:"agent-nick.png", portrait:2 },
        { key:"robby", name:"Robby", area:"Документы", description:"Находит информацию в документах и помогает со сводками.", tint:"#efe7f0", image:"agent-robby.png", portrait:3 }
    ]
    readonly property var pageTitles: ({home:"Главная",tasks:"Контроль поручений",meetings:"Совещания",mail:"Анализ почты",calendar:"Календарь",documents:"Документы",knowledge:"База знаний",users:"Пользователи",analytics:"Аналитика",chat:"ИИ-ассистент",settings:"Настройки",audit:"Журнал аудита"})
    readonly property var agentNames: ({eva:"Eva",leo:"Leo",nick:"Nick",robby:"Robby"})
    readonly property var features: ({
        control:  {mode:"task-review", tint:"#d7eadb", title:"Контроль выполнения поручений", glyph:"☑", agent:"leo", ctx:["task"], open:{label:"Открыть задачи →", page:"tasks"},
                   sub:"Кто что делает, где срыв сроков и кого напомнить", placeholder:"Например: покажи просрочки по производству и кому напомнить (можно оставить пустым)",
                   prompt:"Проанализируй поручения сотрудников: выдели просроченные и рискованные, предложи кому и какое напоминание отправить. Отвечай кратко, списком."},
        summary:  {mode:"summary", tint:"#e6def0", title:"Формирование саммери", glyph:"✦", agent:"robby", ctx:["meeting","document"], needInput:false,
                   sub:"Краткая выжимка из встреч, переписки и документов", placeholder:"Вставьте текст для саммери или оставьте пустым — возьму встречи и документы из Focus",
                   prompt:"Составь краткое саммери (5–7 пунктов): главное, решения, риски, следующие шаги. Не выдумывай фактов."},
        replies:  {mode:"reply", tint:"#f4dfd9", title:"Генерация ответов", glyph:"✉", agent:"eva", reply:true, needInput:true,
                   sub:"Вежливый и точный ответ на входящее письмо", placeholder:"Вставьте входящее сообщение и, если нужно, задайте тон ответа",
                   prompt:"Подготовь ответ на входящее сообщение. Деловой вежливый тон, без выдуманных фактов. Верни готовый текст и 2 коротких варианта."},
        docs:     {mode:"writer", tint:"#e7e0ed", title:"Формирование документов", glyph:"▤", agent:"robby", ctx:["document"], needInput:true,
                   sub:"Черновик служебной записки, приказа, регламента или письма", placeholder:"Какой документ нужен и для кого? Например: служебная записка о переносе сроков",
                   prompt:"Подготовь черновик документа со структурой: заголовок, основание, содержание, срок, ответственный. Поля, которых не хватает, отметь [уточнить]."},
        planner:  {mode:"planner", tint:"#dfe9f2", title:"Планирование рабочего дня", glyph:"◔", agent:"nick", ctx:["task","meeting"], open:{label:"Открыть встречи →", page:"meetings"},
                   sub:"План дня по приоритетам, встречам и срокам", placeholder:"Ограничения на сегодня (необязательно): например, нужен час на отчёт",
                   prompt:"Составь план рабочего дня по времени: приоритеты, встречи, блоки концентрации, перерывы. Учти срочные задачи."},
        inbox:    {mode:"inbox", tint:"#f3e5d9", title:"Сортировка входящей почты", glyph:"✉", agent:"eva", reply:true, needInput:true,
                   sub:"Срочное, на ответ, к делегированию, в архив", placeholder:"Вставьте список писем (тема + отправитель + пара строк)",
                   prompt:"Отсортируй входящие письма по группам: срочно, ответить сегодня, делегировать, к сведению, архив. Для каждого — одно действие."},
        meetings: {mode:"meeting", tint:"#dce6f1", title:"Организация встреч", glyph:"▦", agent:"nick", ctx:["meeting"], open:{label:"Открыть встречи →", page:"meetings"},
                   sub:"Время, участники, цель и подготовка", placeholder:"Какую встречу организовать? Цель, участники, желаемое время",
                   prompt:"Предложи организацию встречи: цель, участники, длительность, 2–3 варианта времени без пересечений, что подготовить заранее."},
        calendar: {mode:"calendar", tint:"#d8e9eb", title:"Управление календарём", glyph:"▥", agent:"nick", ctx:["meeting"],
                   sub:"Конфликты, окна и переносы", placeholder:"Что сделать с календарём? Например: найти окно на 1 час на этой неделе",
                   prompt:"Проанализируй календарь: найди конфликты и свободные окна, предложи переносы. Учитывай тестовые данные Focus."},
        agenda:   {mode:"agenda", tint:"#e3e8d6", title:"Повестки и вопросы к совещаниям", glyph:"☰", agent:"nick", ctx:["meeting","document"], open:{label:"Открыть встречи →", page:"meetings"},
                   sub:"Повестка и вопросы на основе рабочих материалов", placeholder:"Тема совещания (необязательно)",
                   prompt:"Подготовь повестку совещания с таймингом и список ключевых вопросов на основе рабочих материалов."},
        approvals:{mode:"approval", tint:"#eee2d7", title:"Согласование документов", glyph:"✔", agent:"robby", ctx:["document","task"], open:{label:"Открыть документы →", page:"documents"},
                   sub:"Статусы согласований и напоминания ответственным", placeholder:"Что проверить? Например: просроченные согласования",
                   prompt:"Определи, какие документы ожидают согласования и у кого, подготовь вежливые напоминания ответственным сотрудникам."},
        reports:  {mode:"report", tint:"#e5e0ed", title:"Управленческие отчёты", glyph:"▥", agent:"robby", ctx:["metrics","task"], open:{label:"Открыть обзор →", page:"analytics"},
                   sub:"Ключевые показатели и выводы для руководителя", placeholder:"За какой период и в каком разрезе нужен отчёт?",
                   prompt:"Сформируй управленческий отчёт: показатели, динамика, отклонения, выводы и рекомендации. Используй только переданные данные."},
        time:     {mode:"time", tint:"#e3eadb", title:"Мониторинг рабочего времени", glyph:"◷", agent:"leo", ctx:["task","meeting"],
                   sub:"Загрузка, переработки и перекосы", placeholder:"Кого или какой период проанализировать?",
                   prompt:"Оцени загрузку и распределение рабочего времени по задачам и встречам, отметь перегрузки и предложи перераспределение."},
        search:   {mode:"search", tint:"#e1e8ef", title:"Поиск и анализ документов", glyph:"⌕", agent:"robby", ctx:["document"], open:{label:"Искать в документах →", page:"documents", search:true},
                   sub:"Найти нужное и сравнить версии", placeholder:"Что найти или проанализировать в документах?",
                   prompt:"Найди в документах информацию по запросу, перечисли источники по номерам и кратко проанализируй различия и риски."},
        delegate: {mode:"delegate", tint:"#f0e4d7", title:"Делегирование задач", glyph:"⇄", agent:"leo", ctx:["task"], open:{label:"＋ Новая задача", action:"task"},
                   sub:"Кому передать — с учётом прав доступа", placeholder:"Какую задачу делегировать и кому? Укажите срок",
                   prompt:"Предложи, кому делегировать задачу и какие полномочия передать, строго с учётом прав доступа и роли. Добавь формулировку поручения."},
        voice:    {mode:"voice", tint:"#f0e0e3", title:"Голосовое управление", glyph:"◉", agent:"eva", voice:true, needInput:true,
                   sub:"Продиктуйте команду: Win + H включает диктовку Windows", placeholder:"Нажмите сюда и продиктуйте (Win + H), например: «Создай задачу подготовить отчёт»",
                   prompt:"Выполни команду руководителя: если нужно, открой раздел или предложи создать задачу."},
        files:    {mode:"files", tint:"#dcebed", title:"Работа с разрешёнными файлами", glyph:"❏", agent:"robby", ctx:["document"], open:{label:"Открыть документы →", page:"documents"},
                   sub:"Только файлы, доступные вашей роли", placeholder:"Что сделать с доступными файлами? Например: кратко описать каждый",
                   prompt:"Работай только с доступными файлами из переданного списка: кратко опиши содержание, отметь устаревшее и дубли."},
        coach:    {mode:"coach", tint:"#f2e3e8", title:"Мотивационный психолог", glyph:"♡", agent:"eva", needInput:false,
                   sub:"Поддержка, фокус и баланс в напряжённый день", placeholder:"Как вы себя чувствуете? Расскажите, что давит (необязательно)",
                   prompt:"Выступи как доброжелательный мотивационный коуч для руководителя: поддержи, предложи 3 коротких практики для фокуса и восстановления. Не ставь диагнозов."},
        employees:{title:"Сотрудники и доступы",glyph:"♙",agent:"leo",sub:"Доступные сотрудники и роли"},
        assistant:{title:"Чат-ассистент",glyph:"✧",agent:"eva",sub:"Диалог с выбранным помощником"},
        security:{title:"Безопасность и журнал",glyph:"◇",agent:"robby",sub:"Защита данных и история действий"}
    })
    readonly property var defaultPinnedFeatures: ["control", "summary", "replies", "docs"]
    readonly property var sideFeatures: ["tasks","meetings","mail","calendar","documents","knowledge","users","analytics","chat","settings","audit"]
    property int workspaceRevision: 0
    property var dashboardData: ({})
    property string exportKind: "pdf"
    property string exportTitle: "Focus"
    property var exportRows: []
    readonly property var sections: ({home:{title:"Главная",icon:"home",feature:"control"},tasks:{title:"Контроль поручений",icon:"control",feature:"control"},meetings:{title:"Совещания",icon:"meetings",feature:"meetings"},mail:{title:"Анализ почты",icon:"inbox",feature:"inbox"},calendar:{title:"Календарь",icon:"calendar",feature:"calendar"},documents:{title:"Документы",icon:"approvals",feature:"docs"},knowledge:{title:"База знаний",icon:"search",feature:"search"},users:{title:"Пользователи",icon:"employees",feature:"employees"},analytics:{title:"Аналитика",icon:"reports",feature:"reports"},chat:{title:"ИИ-ассистент",icon:"assistant",feature:"assistant"},settings:{title:"Настройки",icon:"settings",feature:"security"},audit:{title:"Журнал аудита",icon:"security",feature:"security"}})
    onRecordsChanged: if (loggedIn) workspaceRevision++
    property string sheetKey: ""
    property string sheetOut: ""
    property string sheetErr: ""
    property bool sheetBusy: false
    property int sheetRun: 0
    function openUtility(kind) {
        utilityRecords = []; utilityError = ""
        utilityTitle = ({employees:"Сотрудники и доступы",security:"Безопасность и журнал",notifications:"Уведомления"})[kind]
        utilityDialog.open()
        if (kind === "employees") {
            api("/directory").then(function(data) {
                utilityRecords = (data.people || []).map(function(x) { return {title:x.name,detail:({admin:"Администратор",director:"Директор",manager:"Руководитель",employee:"Сотрудник"})[x.role] + " · " + x.department + (x.active ? "" : " · заблокирован")} })
            }).catch(function(e) { utilityError = e.message })
        } else if (kind === "notifications") {
            api("/notifications/check",{}).then(function() { return api("/notifications") }).then(function(data) {
                utilityRecords = (data.notifications || []).map(function(x) { return {title:x.reason,detail:"Объект №" + x.object_id + " · " + formatDate(x.created)} })
                if (!utilityRecords.length) utilityError = "Новых уведомлений нет"
            }).catch(function(e) { utilityError = e.message })
        } else {
            api("/security/status").then(function(data) {
                let rows = [{title:"Хранение паролей",detail:data.passwords},{title:"Шифрование содержимого",detail:data.storage + "\n" + data.scope},{title:"Целостность журнала",detail:data.audit_integrity ? "Цепочка записей проверена" : "Обнаружено нарушение целостности"}]
                utilityRecords = rows
                if (data.audit_access) api("/admin/audit").then(function(audit) {
                    utilityRecords = rows.concat((audit.events || []).slice(0,40).map(function(x) { return {title:x.action + " · " + x.result,detail:formatDate(x.at) + " · " + (x.detail || "")} }))
                }).catch(function(e) { utilityError = e.message })
            }).catch(function(e) { utilityError = e.message })
        }
    }
    function openFeature(key) {
        if (key === "assistant") { openAgent(agent); return }
        if (key === "employees" || key === "security") { openUtility(key); return }

        sheetRun++
        sheetKey = key; sheetOut = ""; sheetErr = ""; sheetBusy = false; featureInput.text = ""
        if (key === "calendar") {
            const start = new Date()
            start.setMinutes(0, 0, 0); start.setHours(start.getHours() + 1)
            calendarStartField.text = start.toLocaleString(Qt.locale("en_US"), "yyyy-MM-dd HH:mm")
            const end = new Date(start.getTime() + 7 * 86400000)
            calendarEndField.text = end.toLocaleString(Qt.locale("en_US"), "yyyy-MM-dd HH:mm")
        }
        featureSheet.open()
    }
    function runFeature() {
        const f = features[sheetKey]
        if (!f || sheetBusy) return
        if (sheetKey === "calendar") { findFreeSlots(); return }
        const user = featureInput.text.trim()
        if (f.needInput && !user) { sheetErr = "Опишите задачу или вставьте текст."; return }
        sheetBusy = true; sheetErr = ""; sheetOut = ""
        const kinds = f.ctx || []
        const key = sheetKey
        const run = ++sheetRun
        let context = ""
        function send() {
            if (run !== sheetRun) return
            const text = f.prompt + (user ? "\n\nЗапрос: " + user : "") + (context ? "\n\nДанные из Focus:\n" + context : "")
            api("/focus/agent", {agent:f.agent, text:text, history:[]}).then(function(data) {
                if (run !== sheetRun || key !== sheetKey) return
                sheetOut = data.answer; sheetBusy = false
                if (f.voice) {
                    if (data.task_title) { featureSheet.close(); newTask(data.task_title) }
                    else if (data.page) { featureSheet.close(); navigate(data.page) }
                }
            }).catch(function(error) { if (run === sheetRun) { sheetErr = error.message; sheetBusy = false } })
        }
        function step(i) {
            if (run !== sheetRun) return
            if (i >= kinds.length) { send(); return }
            const k = kinds[i]
            api(k === "metrics" ? "/dashboard" : "/objects?kind=" + k).then(function(d) {
                if (k === "metrics") {
                    context += "Показатели: " + (d.metrics || []).map(function(m) { return m.id + "=" + (m.value === null ? "нет данных" : m.value + " " + m.unit) }).join("; ") + "\n"
                } else {
                    const list = (d.objects || []).slice(0, 15).map(function(o) {
                        const x = o.data || {}
                        return "- " + o.title + (x.status ? " [" + x.status + "]" : "") + (x.due ? " срок " + formatDate(x.due) : "") + (x.start ? " начало " + formatDate(x.start) : "")
                    })
                    context += ({task:"Задачи", meeting:"Встречи", document:"Документы"})[k] + ":\n" + list.join("\n") + "\n"
                }
            }).then(function() { step(i + 1) }).catch(function(error) {
                if (run === sheetRun) { sheetErr = error.message; sheetBusy = false }
            })
        }
        step(0)
    }
    palette.window: bg
    palette.base: surface
    palette.text: ink
    palette.windowText: ink
    palette.buttonText: ink
    palette.button: surface
    palette.highlight: accent
    palette.highlightedText: "white"
    palette.placeholderText: muted

    FocusBackend {
        id: backend
        onResponse: function(id, data, error) {
            const callback = win.callbacks[id]
            delete win.callbacks[id]
            if (callback) callback(data, error)
        }
        onRestarting: win.clearSession()
        onFeatureError: function(message) { win.toast(message) }
        onRecordingSaved: function(path) {
            if (!win.loggedIn) { win.chatRecording = false; win.chatAudioUrl = ""; return }
            if (win.chatRecording) { win.chatAudioUrl = String(path); win.chatRecording = false; win.toast("Запись готова. «Распознать» отправит её OpenAI.") }
            else if (workspaceLoader.item) workspaceLoader.item.receivedRecording(path)
        }
    }
    ListModel { id: conversation }
    Timer { id: noticeTimer; interval: 6000; onTriggered: win.notice = "" }
    Component.onCompleted: {
        const saved = backend.loadPinnedFeatures()
        let valid = saved.length === 4
        const seen = ({})
        for (let i = 0; valid && i < saved.length; i++) {
            valid = saved[i] === "" || (!!features[saved[i]] && !seen[saved[i]])
            seen[saved[i]] = true
        }
        if (valid) pinnedFeatures = saved
    }
    function api(path, body) {
        const epoch = sessionEpoch
        return new Promise(function(resolve, reject) {
            const id = body === undefined ? backend.request(path) : backend.request(path, body)
            callbacks[id] = function(data, error) {
                if (epoch !== sessionEpoch) return
                if (error) {
                    // сессия истекла или недействительна: возвращаем на экран входа, а не оставляем окно «мёртвым»
                    if (win.loggedIn && win.isAuthFailure(path, error)) { win.sessionExpired(); return }
                    reject(new Error(error))
                } else resolve(data)
            }
        })
    }
    function agentInfo(key) { for (let i = 0; i < agents.length; i++) if (agents[i].key === key) return agents[i]; return agents[0] }
    function pinFeature(slot, key) {
        if (slot < 0 || slot > 3 || !features[key]) return
        const updated = pinnedFeatures.slice(0, 4)
        while (updated.length < 4) updated.push("")
        const source = updated.indexOf(key)
        const replaced = updated[slot]
        if (source >= 0 && source !== slot) updated[source] = replaced || ""
        updated[slot] = key
        pinnedFeatures = updated
        backend.savePinnedFeatures(updated)
        toast(features[key].title + " закреплена сверху")
    }
    function unpinFeature(slot) {
        const updated = pinnedFeatures.slice(0, 4)
        updated[slot] = ""
        pinnedFeatures = updated
        backend.savePinnedFeatures(updated)
    }
    function showPinPicker(slot) { pinSlotToFill = slot; pinPicker.open() }
    function attachHomeFile(fileUrl) {
        homeAttachedFileUrl = fileUrl
        const tail = fileUrl.substring(fileUrl.lastIndexOf("/") + 1)
        try { homeAttachedFileName = decodeURIComponent(tail) } catch (e) { homeAttachedFileName = tail }
        toast("Файл добавлен к запросу")
    }
    function clearHomeQuery() {
        homeQueryText = ""
        if (homeLoader.item) homeLoader.item.searchText = ""
    }
    function sendHomePrompt() {
        if (homeSearchBusy || chatBusy) return
        const question = homeQueryText.trim()
        if (!question && !homeAttachedFileUrl) return
        homeSearchBusy = true
        function continueWith(text) {
            openAgent(agent)
            prompt.text = text.slice(0, 11000)
            clearHomeQuery()
            homeAttachedFileUrl = ""; homeAttachedFileName = ""
            homeSearchBusy = false
            Qt.callLater(function() { win.sendPrompt() })
        }
        if (!homeAttachedFileUrl) {
            continueWith(question)
            return
        }
        api("/documents/import", {path:homeAttachedFileUrl}).then(function(imported) {
            return api("/objects/" + imported.id)
        }).then(function(result) {
            const object = result.object || ({})
            const content = String((object.data || {}).text || "").slice(0, 8500)
            const safeQuestion = question.slice(0, 1800)
            continueWith((safeQuestion || "Прочитай документ и подготовь краткую выжимку.") +
                "\n\nФайл: " + (object.title || homeAttachedFileName) + "\nСодержимое:\n" + content)
            toast("Документ добавлен в библиотеку и приложен к запросу")
        }).catch(function(error) {
            homeSearchBusy = false
            toast(error.message)
        })
    }
    function logout() { api("/auth/logout", {}).then(function() { clearSession() }).catch(function() { clearSession() }) }
    function toast(text) { notice = text; noticeTimer.restart() }
    function formatDate(value) { return value ? new Date(value).toLocaleString(Qt.locale("ru_RU"), "dd.MM.yyyy HH:mm") : "не указан" }
    function clearSession() {
        if (backend.recording) backend.stopMeetingRecording()
        chatRecording = false; chatAudioUrl = ""
        sheetRun++; sheetBusy = false; sheetOut = ""; sheetErr = ""; featureSheet.close()
        sessionEpoch++; callbacks = ({}); loggedIn = false; userName = ""; backend.setToken("")
        pinPicker.close(); homeAttachedFileUrl = ""; homeAttachedFileName = ""; clearHomeQuery()
        chatOpen = false; chatBusy = false; loginBusy = false; history = []; conversation.clear()
        records = []; metrics = []; folders = []; selectedFolderId = -1; documentSearchText = ""
        page = "home"; agent = "eva"; loading = false; pageRequest++
        taskDialog.close(); folderDialog.close(); documentDialog.close(); meetingDialog.close()
        messageDialog.close(); confirmDialog.close(); detailDialog.close(); intro.stop()
        confirmDialog.working = false; messageDialog.improving = false
        recipient.text = ""; messageBody.text = ""; notice = ""
        resetAuth(); userRole = ""; utilityRecords = []; utilityDialog.close()
    }
    function isAuthFailure(path, error) {
        const text = String(error)
        return String(path).indexOf("/auth/") !== 0 && (text.indexOf("Сессия недействительна") === 0 || text.indexOf("Войдите в систему") === 0)
    }
    function sessionExpired() {
        clearSession(); showAuth("login"); loginError = "Сессия истекла. Войдите снова."
    }
    function showAuth(mode) {
        if (loginBusy) return
        loginError = ""; authMode = mode
        focusTimer.target = mode === "login" ? username.input : (mode === "register" ? regName.input : null)
        if (focusTimer.target) focusTimer.restart()
    }
    function resetAuth() {
        authMode = "welcome"; loginError = ""; loginBusy = false
        username.text = ""; password.text = ""; password.reveal = false
        regName.text = ""; regUser.text = ""; regPass.text = ""; regPass2.text = ""; regPass.reveal = false; regPass2.reveal = false
    }
    function passwordScore(p) {
        if (p.length < 8) return 0
        let classes = 0
        if (/[a-zа-яё]/.test(p)) classes++
        if (/[A-ZА-ЯЁ]/.test(p)) classes++
        if (/\d/.test(p)) classes++
        if (/[^A-Za-zА-Яа-яЁё0-9]/.test(p)) classes++
        let score = 1
        if (classes >= 3 || (classes >= 2 && p.length >= 10)) score = 2
        if (classes >= 3 && p.length >= 12) score = 3
        return score
    }
    function strengthText(p) { return ["Минимум 8 символов", "Простой пароль", "Хороший пароль", "Надёжный пароль"][passwordScore(p)] }
    function strengthColor(score) { return score >= 3 ? "#34c759" : (score === 2 ? "#8fc93a" : "#ff9f0a") }
    function signUp() {
        if (loginBusy) return
        if (!backend.ready) { loginError = "Сервер ещё запускается — подождите несколько секунд"; return }
        const name = regName.text.trim().replace(/\s+/g, " ")
        const user = regUser.text.trim().toLowerCase()
        const pass = regPass.text
        let problem = ""
        if (name.length < 2) problem = "Введите имя — не короче 2 символов"
        else if (name.length > 60) problem = "Имя не должно быть длиннее 60 символов"
        else if (!/^[a-z0-9._-]{3,32}$/.test(user)) problem = "Логин: 3–32 символа — латиница, цифры, точка, дефис или подчёркивание"
        else if (pass.length < 8) problem = "Пароль должен содержать не менее 8 символов"
        else if (pass.length > 200) problem = "Пароль не должен быть длиннее 200 символов"
        else if (pass.toLowerCase() === user) problem = "Пароль не должен совпадать с логином"
        else if (pass !== regPass2.text) problem = "Пароли не совпадают"
        if (problem.length > 0) { loginError = problem; return }
        loginBusy = true; loginError = ""
        api("/auth/register", {name:name,username:user,password:pass}).then(function(data) {
            backend.setToken(data.token); userName = data.name; userRole = data.role; loggedIn = true; loginBusy = false
            regPass.text = ""; regPass2.text = ""; navigate("home")
        }).catch(function(error) { loginError = error.message; loginBusy = false })
    }
    function login() {
        if (loginBusy) return
        if (!backend.ready) { loginError = "Сервер ещё запускается — подождите несколько секунд"; return }
        const user = username.text.trim()
        if (user.length === 0 || password.text.length === 0) { loginError = "Введите логин и пароль"; return }
        loginBusy = true; loginError = ""
        api("/auth/login", {username:user,password:password.text}).then(function(data) {
            backend.setToken(data.token); userName = data.name; userRole = data.role; loggedIn = true; loginBusy = false; password.text = ""; navigate("home")
        }).catch(function(error) { loginError = error.message; loginBusy = false })
    }
    function navigate(target) {
        if (!loggedIn || !pageTitles[target]) return
        if (target === "chat") { page = "chat"; openAgent(agent); return }
        chatOpen = false
        workspaceRevision++
        if (target === "home") api("/workspace/analytics").then(function(value) { dashboardData = value }).catch(function(error) { toast(error.message) })
        page = target; records = []; metrics = []; pageError = ""; loading = false
        if (target === "documents") {
            documentSearchText = ""
            loadDocuments(-1)
            return
        }
        const request = ++pageRequest
        const paths = {tasks:"/objects?kind=task", meetings:"/objects?kind=meeting", analytics:"/dashboard"}
        if (!paths[target]) return
        loading = true
        api(paths[target]).then(function(data) {
            if (request !== pageRequest) return
            records = data.objects || []; metrics = data.metrics || []; loading = false
        }).catch(function(error) { if (request === pageRequest) { pageError = error.message; loading = false } })
    }
    function loadDocuments(folderId) {
        if (folderId !== undefined) selectedFolderId = folderId
        const request = ++pageRequest
        documentSearchText = ""
        pageError = ""; loading = true; records = []; folders = []
        const query = selectedFolderId > 0 ? "?folder_id=" + selectedFolderId : ""
        api("/folders").then(function(folderData) {
            if (request !== pageRequest) return null
            folders = folderData.folders || []
            return api("/documents/library" + query)
        }).then(function(data) {
            if (request !== pageRequest || !data) return
            records = data.documents || []; loading = false
        }).catch(function(error) {
            if (request === pageRequest) { pageError = error.message; loading = false }
        })
    }
    function searchDocuments(query) {
        page = "documents"
        documentSearchText = String(query || "").trim()
        if (!documentSearchText) { loadDocuments(-1); return }
        selectedFolderId = -1
        loading = true; pageError = ""
        const request = ++pageRequest
        api("/documents/search?q=" + encodeURIComponent(documentSearchText)).then(function(data) {
            if (request === pageRequest) { records = data.results; loading = false }
        }).catch(function(error) { if (request === pageRequest) { pageError = error.message; loading = false } })
    }
    function folderNames() {
        let names = ["Все документы"]
        for (let i = 0; i < folders.length; i++) names.push(folders[i].name)
        return names
    }
    function folderIndex(id) {
        for (let i = 0; i < folders.length; i++) if (folders[i].id === id) return i
        return -1
    }
    function folderName(id) {
        const index = folderIndex(id)
        return index < 0 ? "Без папки" : folders[index].name
    }
    function newFolder() {
        folderNameField.text = ""; folderError.text = ""; folderBusy = false
        folderDialog.open()
    }
    function saveFolder() {
        const name = folderNameField.text.trim()
        if (!name || folderBusy) return
        folderBusy = true; folderError.text = ""
        api("/folders", {name:name}).then(function(data) {
            folderDialog.close(); selectedFolderId = data.folder.id; loadDocuments(selectedFolderId)
            toast("Папка создана")
        }).catch(function(error) { folderError.text = error.message }).then(function() { folderBusy = false })
    }
    function newDocument() {
        documentTitleField.text = ""; documentBodyField.text = ""; documentError.text = ""
        documentFolderBox.currentIndex = selectedFolderId > 0 ? folderIndex(selectedFolderId) + 1 : 0
        documentDialog.open()
    }
    function saveDocument() {
        const title = documentTitleField.text.trim()
        const text = documentBodyField.text.trim()
        if (!title || !text || documentBusy) return
        const folderId = documentFolderBox.currentIndex > 0 ? folders[documentFolderBox.currentIndex - 1].id : null
        documentBusy = true; documentError.text = ""
        api("/documents", {title:title,text:text,folder_id:folderId,format:"txt"}).then(function() {
            documentDialog.close(); selectedFolderId = folderId || -1; loadDocuments()
            toast("Документ сохранён")
        }).catch(function(error) { documentError.text = error.message }).then(function() { documentBusy = false })
    }
    function importDocument(fileUrl) {
        const folderId = selectedFolderId > 0 ? selectedFolderId : null
        loading = true; pageError = ""
        api("/documents/import", {path:fileUrl,folder_id:folderId}).then(function(result) {
            selectedFolderId = folderId || -1
            toast("Добавлен документ: " + result.title)
            loadDocuments()
        }).catch(function(error) { pageError = error.message; loading = false })
    }
    function openDocument(id) {
        api("/objects/" + id).then(function(data) {
            detailDialog.title = data.object.title
            detailText.text = data.object.data.text || "Текст недоступен"
            detailDialog.open()
        }).catch(function(error) { toast(error.message) })
    }
    function newMeeting() {
        meetingTitleField.text = ""; meetingAgendaField.text = ""; meetingError.text = ""
        const start = new Date(Date.now() + 3600000)
        start.setMinutes(0, 0, 0)
        const end = new Date(start.getTime() + 3600000)
        meetingStartField.text = start.toLocaleString(Qt.locale("en_US"), "yyyy-MM-dd HH:mm")
        meetingEndField.text = end.toLocaleString(Qt.locale("en_US"), "yyyy-MM-dd HH:mm")
        meetingDialog.open()
    }
    function reviewMeeting() {
        meetingError.text = ""
        const title = meetingTitleField.text.trim()
        const start = Date.fromLocaleString(Qt.locale("en_US"), meetingStartField.text.trim(), "yyyy-MM-dd HH:mm")
        const end = Date.fromLocaleString(Qt.locale("en_US"), meetingEndField.text.trim(), "yyyy-MM-dd HH:mm")
        if (!title) { meetingError.text = "Укажите название встречи."; return }
        if (isNaN(start.getTime()) || isNaN(end.getTime()) || end <= start) { meetingError.text = "Проверьте дату и время начала и окончания."; return }
        const data = {start:start.toISOString(),end:end.toISOString(),agenda:meetingAgendaField.text.trim()}
        prepare("create_object", {kind:"meeting",title:title,data:data,visibility:"private"},
                "Встреча: " + title + "\nНачало: " + formatDate(data.start) + "\nОкончание: " + formatDate(data.end) + "\nПовестка: " + (data.agenda || "не указана"), "meetings")
    }
    function toggleTask(record) {
        const data = JSON.parse(JSON.stringify(record.data || {}))
        const done = ["завершена","done","completed","выполнена"].indexOf(String(data.status || "").toLowerCase()) >= 0
        data.status = done ? "открыта" : "завершена"
        prepare("update_object", {id:record.id,version:record.version,data:data},
                (done ? "Вернуть в работу: " : "Завершить: ") + record.title, "tasks")
    }
    function findFreeSlots() {
        const start = Date.fromLocaleString(Qt.locale("en_US"), calendarStartField.text.trim(), "yyyy-MM-dd HH:mm")
        const end = Date.fromLocaleString(Qt.locale("en_US"), calendarEndField.text.trim(), "yyyy-MM-dd HH:mm")
        if (isNaN(start.getTime()) || isNaN(end.getTime()) || end <= start) { sheetErr = "Проверьте начало и конец периода."; return }
        sheetBusy = true; sheetErr = ""; sheetOut = ""
        api("/calendar/free", {start:start.toISOString(),end:end.toISOString(),duration_minutes:Number(calendarDuration.currentText)}).then(function(data) {
            const slots = data.slots || []
            sheetOut = slots.length
                ? "Свободные окна (" + data.calendar + "):\n" + slots.map(function(x) { return formatDate(x.start) + " — " + formatDate(x.end) }).join("\n")
                : "Свободных окон с выбранной длительностью не найдено."
            sheetBusy = false
        }).catch(function(error) { sheetErr = error.message; sheetBusy = false })
    }
    function openAgent(key) {
        agent = key; chatOpen = true; prompt.forceActiveFocus(); intro.stop()
        if (conversation.count === 0) api("/workspace/chat").then(function(value) {
            if (conversation.count || chatBusy) return
            const messages = value.chat || []
            messages.slice(-40).forEach(function(item) { bubble(item.role === "user" ? "Вы" : (agentNames[item.agent] || "Focus"),item.text) })
            history = messages.slice(-10).map(function(item) { return {role:item.role,text:item.text} })
        }).catch(function() {})
    }
    function bubble(who, text) {
        conversation.append({who:who, body:text})
        Qt.callLater(function() { chatList.positionViewAtEnd() })
    }
    function sendPrompt() {
        if (homeAttachedFileUrl) { homeQueryText = prompt.text; sendHomePrompt(); return }
        const text = prompt.text.trim()
        if (!text || chatBusy) return
        const selected = agent
        bubble("Вы", text); prompt.text = ""; chatBusy = true
        api("/focus/agent", {agent:selected,text:text,history:history.slice(-10)}).then(function(data) {
            if (data.handoff) { bubble("Focus", "Передаю запрос агенту " + agentNames[data.agent] + "."); agent = data.agent }
            let answer = data.answer
            if (data.sources && data.sources.length) answer += "\n\nИсточники: " + data.sources.map(function(s) { return "№" + s.id + " " + s.title }).join("; ")
            bubble(agentNames[data.agent] || "Focus", answer)
            history = history.concat([{role:"user",text:text},{role:"assistant",text:data.answer}]).slice(-10)
            chatBusy = false
            if (data.page) navigate(data.page)
            if (data.task_title) newTask(data.task_title)
        }).catch(function(error) { chatBusy = false; bubble("Focus", error.message) })
    }
    function checkAi() {
        if (chatBusy) return
        chatBusy = true
        api("/focus/check", {agent:agent}).then(function(data) {
            bubble("Focus", data.provider + ": " + data.message); chatBusy = false
        }).catch(function(error) { bubble("Focus", error.message); chatBusy = false })
    }
    function newTask(title) { taskTitle.text = title || ""; taskDue.text = ""; taskError.text = ""; taskDialog.open() }
    function prepare(kind, payload, preview, refreshPage) {
        confirmDialog.working = true
        api("/proposals", {kind:kind,payload:payload,idempotency_key:backend.newKey()}).then(function(data) {
            taskDialog.close(); messageDialog.close(); meetingDialog.close()
            confirmDialog.proposalId = data.proposal_id; confirmDialog.kind = kind
            confirmDialog.refreshPage = refreshPage || (kind === "create_object" && payload.kind === "meeting" ? "meetings" : "tasks")
            confirmDialog.preview = preview; confirmDialog.working = false; confirmDialog.errorText = ""; confirmDialog.open()
        }).catch(function(error) { confirmDialog.working = false; taskError.text = error.message; messageError.text = error.message; toast(error.message) })
    }
    component Copy: Label { color: win.ink; textFormat: Text.PlainText; wrapMode: Text.WordWrap }
    component Hint: Copy { color: win.muted; font.pixelSize: 12 }
    component Action: Button {
        id: control
        property bool primary: false
        property bool selected: false
        implicitHeight: 42; leftPadding: 18; rightPadding: 18
        font.pixelSize: 13; font.weight: Font.DemiBold
        contentItem: Text {
            text: control.text; font: control.font; color: control.primary ? "white" : win.ink
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            opacity: control.enabled ? 1 : 0.5
        }
        background: Rectangle {
            radius: height / 2
            color: control.primary ? (control.down ? "#5c4c85" : (control.hovered ? "#7c6ba8" : win.accent))
                                   : (control.selected || control.hovered ? (backend.dark ? "#45ffffff" : "#d9ffffff") : win.glass)
            border.color: control.activeFocus ? win.accent : (control.primary ? win.accent : win.glassEdge)
            border.width: control.activeFocus ? 2 : 1; opacity: control.enabled ? 1 : 0.45
            gradient: Gradient {
                GradientStop { position: 0.0; color: control.primary ? "#a99ac6" : (backend.dark ? "#605064" : "#faffffff") }
                GradientStop { position: 0.42; color: control.primary ? "#736087" : (backend.dark ? "#302b3a" : "#72ffffff") }
                GradientStop { position: 1.0; color: control.primary ? "#8c7aab" : (backend.dark ? "#484252" : "#c9e3e3f1") }
            }
            Rectangle { anchors { fill: parent; margins: 3 } radius: height / 2; color: "transparent"; border.width: 1; border.color: "#60ffffff" }
        }
        scale: down ? 0.97 : hovered ? 1.025 : 1
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Accessible.name: text
    }
    component Field: TextField {
        id: control
        implicitHeight: 44; color: win.ink; selectByMouse: true; leftPadding: 18; rightPadding: 18
        background: Rectangle { color: win.glass; radius: height / 2; border.width: control.activeFocus ? 2 : 1; border.color: control.activeFocus ? win.accent : win.fieldEdge }
    }
    component Panel: Rectangle {
        color: win.glass; radius: 28; border.color: win.glassEdge; border.width: 1.5
        Rectangle { height: 1.5; radius: 1; anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right; leftMargin: 26; rightMargin: 26 } color: "white"; opacity: 0.8 }
    }
    component AnimatedDialog: Dialog {
        enter: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 } NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutCubic } } }
        exit: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 } NumberAnimation { property: "scale"; from: 1; to: 0.96; duration: 150 } } }
    }
    component DialogBack: Rectangle {
        radius: 32; color: backend.dark ? "#f2262830" : "#f7f4f4f6"; border.color: win.glassEdge; border.width: 1.5
        Rectangle { height: 1.5; radius: 1; anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right; leftMargin: 30; rightMargin: 30 } color: "white"; opacity: 0.9 }
    }
    component RailButton: Rectangle {
        id: rb
        property string glyph: ""
        property string tip: ""
        property bool selected: false
        signal clicked()
        implicitWidth: 42; implicitHeight: 42; radius: 21
        color: selected ? win.accent : (ma.containsMouse ? (backend.dark ? "#35ffffff" : "#b3ffffff") : "transparent")
        Text { anchors.centerIn: parent; text: rb.glyph; font.pixelSize: 17; color: rb.selected ? "white" : win.ink }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
        ToolTip.visible: ma.containsMouse && tip.length > 0; ToolTip.text: tip; ToolTip.delay: 400
        Accessible.role: Accessible.Button; Accessible.name: tip; Accessible.onPressAction: rb.clicked()
    }
    component Chip: Item {
        id: chip
        property string label: ""
        property string value: ""
        signal clicked()
        implicitWidth: chipCol.implicitWidth + 36; implicitHeight: 56
        Column {
            id: chipCol; anchors.centerIn: parent; spacing: 1
            Text { text: chip.label; font.pixelSize: 10; color: win.muted }
            Text { text: chip.value; font.pixelSize: 14; font.weight: Font.DemiBold; color: win.ink }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label + " " + value
    }
    component RoundBtn: Rectangle {
        id: rbtn
        property string icon: ""
        property string glyph: "↗"
        property bool selected: false
        property int size: 44
        signal clicked()
        implicitWidth: size; implicitHeight: size; radius: size / 2
        color: selected ? win.accent : (backend.dark ? (rma.containsMouse ? "#45ffffff" : "#25ffffff") : (rma.containsMouse ? "#f2ffffff" : "#b3ffffff"))
        border.color: win.glassEdge
        gradient: Gradient { GradientStop { position: 0; color: rbtn.selected ? "#aa98c9" : "#fcffffff" } GradientStop { position: 0.48; color: rbtn.selected ? "#7f6c9d" : "#60ffffff" } GradientStop { position: 1; color: rbtn.selected ? "#9a89bb" : "#d4deedfb" } }
        scale: rma.pressed ? 0.96 : rma.containsMouse ? 1.07 : 1
        Behavior on scale { NumberAnimation { duration: 160 } }
        Image { anchors.centerIn: parent; width: rbtn.size * 0.42; height: width; visible: rbtn.icon.length > 0; source: rbtn.icon ? backend.assets + "icons/" + rbtn.icon + ".svg" : "" }
        Text { visible: !rbtn.icon; anchors.centerIn: parent; text: rbtn.glyph; font.pixelSize: rbtn.size * 0.38; font.weight: Font.DemiBold; color: rbtn.selected ? "white" : win.ink }
        MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rbtn.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: glyph; Accessible.onPressAction: rbtn.clicked()
    }

    component AvatarPortrait: Image {
        property int portraitIndex: 0
        source: backend.assets + win.agents[portraitIndex].image
        fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
    }
    component GlassField: TextField {
        id: gf
        implicitHeight: 48; color: "#2b211b"; selectByMouse: true; leftPadding: 18; rightPadding: 18
        font.pixelSize: 14; placeholderTextColor: "#a8968a"; selectionColor: "#8a8290"
        background: Rectangle {
            radius: 24; color: gf.activeFocus ? "#e6ffffff" : "#a6ffffff"
            border.width: gf.activeFocus ? 2 : 1; border.color: gf.activeFocus ? "#8a8290" : "#ccffffff"
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    component Glow: Item {
        id: glow
        property color tint: "#8ff7ff"
        property real radiusPx: 320
        property real anchorX: 0
        property real anchorY: 0
        property real driftX: 70
        property real driftY: 50
        property int driftMs: 9000
        property int pulseMs: 5200
        property real lo: 0.2
        property real hi: 0.8
        property real dx: 0
        property real dy: 0
        width: radiusPx * 2; height: radiusPx * 2
        x: anchorX - radiusPx + dx
        y: anchorY - radiusPx + dy
        opacity: 0.4
        SequentialAnimation on opacity {
            running: win.authVisible; loops: Animation.Infinite
            NumberAnimation { to: glow.hi; duration: glow.pulseMs; easing.type: Easing.InOutSine }
            NumberAnimation { to: glow.lo; duration: glow.pulseMs; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on dx {
            running: win.authVisible; loops: Animation.Infinite
            NumberAnimation { to: glow.driftX; duration: glow.driftMs; easing.type: Easing.InOutSine }
            NumberAnimation { to: -glow.driftX; duration: glow.driftMs; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on dy {
            running: win.authVisible; loops: Animation.Infinite
            NumberAnimation { to: -glow.driftY; duration: glow.driftMs * 1.3; easing.type: Easing.InOutSine }
            NumberAnimation { to: glow.driftY; duration: glow.driftMs * 1.3; easing.type: Easing.InOutSine }
        }
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: glow.radiusPx; centerY: glow.radiusPx; centerRadius: glow.radiusPx
                    focalX: glow.radiusPx; focalY: glow.radiusPx
                    GradientStop { position: 0.0; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, 0.95) }
                    GradientStop { position: 0.45; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, 0.40) }
                    GradientStop { position: 1.0; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, 0.0) }
                }
                startX: 0; startY: 0
                PathLine { x: glow.width; y: 0 }
                PathLine { x: glow.width; y: glow.height }
                PathLine { x: 0; y: glow.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // Продолговатая «стеклянная» плашка: полупрозрачная заливка, световая кромка, мягкая тень
    component GlassBar: Item {
        id: gb
        property bool hot: false
        property bool pressed: false
        property bool focused: false
        property real corner: Math.min(height / 2, 40)
        property real lift: (hot || focused) ? 1 : 0
        property real shadowStrength: 0.26
        default property alias content: slot.data
        implicitHeight: 58
        scale: pressed ? 0.985 : (hot ? 1.012 : 1.0)
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on lift { NumberAnimation { duration: 200 } }
        Rectangle { // кольцо фокуса
            anchors.fill: parent; anchors.margins: -4; radius: gb.corner + 4
            color: "transparent"; border.width: 3; border.color: "#7a8f9bff"
            opacity: gb.focused ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
        Item {
            id: body
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: "#5b4fc0"
                shadowOpacity: gb.shadowStrength + 0.10 * gb.lift
                shadowBlur: 1.0; shadowVerticalOffset: 6 + 4 * gb.lift
            }
            Rectangle {
                anchors.fill: parent; radius: gb.corner
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.55 + 0.35 * gb.lift)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.50 + 0.14 * gb.lift) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.18 + 0.12 * gb.lift) }
                }
            }
            Rectangle { // блик вдоль верхней кромки
                height: 1.5; radius: 1
                anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right; leftMargin: gb.corner * 0.8; rightMargin: gb.corner * 0.8 }
                color: "white"; opacity: 0.85
            }
        }
        Item { id: slot; anchors.fill: parent }
    }

    component ChoiceBar: GlassBar {
        id: cb
        property string title: ""
        property string subtitle: ""
        property string glyph: ""
        signal clicked()
        implicitHeight: Math.max(76, Math.min(92, loginPage.width * 0.065))
        corner: height / 2; shadowStrength: 0.08
        hot: cma.containsMouse
        pressed: cma.pressed
        Rectangle {
            id: badge
            width: cb.height * 0.72; height: width; radius: width / 2
            x: cb.height * 0.28; anchors.verticalCenter: parent.verticalCenter
            color: "#66ffffff"; border.width: 1; border.color: "#b3ffffff"
            Text { anchors.centerIn: parent; text: cb.glyph; font.pixelSize: 22; color: "#2a2a35" }
        }
        Column {
            anchors { left: badge.right; leftMargin: 24; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { text: cb.title; color: "#10151c"; font.family: win.uiFont; font.pixelSize: 21; font.weight: Font.DemiBold }
            Text { text: cb.subtitle; color: "#535d78"; font.family: win.uiFont; font.pixelSize: 15 }
        }
        Text {
            id: chevron
            anchors.verticalCenter: parent.verticalCenter
            x: cb.width - width - (cb.hot ? 26 : 32)
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            text: "›"; font.pixelSize: 30; color: "#17171c"; opacity: cb.hot ? 1.0 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: title; Accessible.onPressAction: cb.clicked()
    }

    component GlassInput: GlassBar {
        id: gi
        property alias text: field.text
        property alias placeholder: field.placeholderText
        property alias input: field
        property bool secret: false
        property bool reveal: false
        signal accepted()
        focused: field.activeFocus
        hot: field.hovered
        TextField {
            id: field
            anchors.fill: parent
            leftPadding: 26; rightPadding: gi.secret ? 96 : 26
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            echoMode: (gi.secret && !gi.reveal) ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            color: "#17171c"; placeholderTextColor: "#8e8ea3"
            selectionColor: "#8c97ff"; selectedTextColor: "white"
            font.family: win.uiFont; font.pixelSize: 16; font.weight: Font.Medium
            background: null
            onAccepted: gi.accepted()
        }
        Text {
            visible: gi.secret
            anchors { right: parent.right; rightMargin: 26; verticalCenter: parent.verticalCenter }
            text: gi.reveal ? "Скрыть" : "Показать"
            font.family: win.uiFont; font.pixelSize: 12; font.weight: Font.DemiBold
            color: revealMouse.containsMouse ? "#17171c" : "#6d6d80"
            MouseArea { id: revealMouse; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: gi.reveal = !gi.reveal }
        }
    }

    component PrimaryButton: Item {
        id: pb
        property string text: ""
        signal clicked()
        implicitHeight: 58
        scale: pma.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent; radius: height / 2
            opacity: pb.enabled ? 1 : 0.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: pma.pressed ? "#101014" : (pma.containsMouse ? "#2a2a35" : "#1b1b22") }
                GradientStop { position: 1.0; color: pma.pressed ? "#23232c" : (pma.containsMouse ? "#42425a" : "#333344") }
            }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#2a2450"; shadowOpacity: 0.38; shadowBlur: 0.9; shadowVerticalOffset: 8 }
            Rectangle {
                height: 1.5; radius: 1
                anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 28 }
                color: "white"; opacity: 0.22
            }
        }
        Text {
            anchors.centerIn: parent; text: pb.text; color: "white"
            font.family: win.uiFont; font.pixelSize: 16; font.weight: Font.DemiBold
            opacity: pb.enabled ? 1 : 0.65
        }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; enabled: pb.enabled; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: text; Accessible.onPressAction: pb.clicked()
    }

    component LinkText: Item {
        id: lt
        property string lead: ""
        property string action: ""
        signal clicked()
        implicitWidth: ltRow.implicitWidth + 12; implicitHeight: 30
        Row {
            id: ltRow; anchors.centerIn: parent; spacing: 6
            Text { text: lt.lead; visible: text.length > 0; color: "#6d6d80"; font.family: win.uiFont; font.pixelSize: 13 }
            Text { text: lt.action; color: "#17171c"; font.family: win.uiFont; font.pixelSize: 13; font.weight: Font.DemiBold; font.underline: lma.containsMouse }
        }
        MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lt.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: lead + " " + action; Accessible.onPressAction: lt.clicked()
    }

    component BackChip: GlassBar {
        id: bc
        signal clicked()
        width: 50; height: 50
        hot: bma.containsMouse; pressed: bma.pressed
        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -2; text: "‹"; font.pixelSize: 30; color: "#17171c" }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bc.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: "Назад"; Accessible.onPressAction: bc.clicked()
    }

    component ErrorPill: Rectangle {
        id: ep
        implicitHeight: msg.implicitHeight + 22
        radius: Math.min(height / 2, 26)
        visible: win.loginError.length > 0
        color: "#26ff5a4a"; border.width: 1; border.color: "#59ff5a4a"
        Text {
            id: msg
            anchors.centerIn: parent; width: Math.max(0, parent.width - 36)
            text: win.loginError; color: "#b3261e"
            font.family: win.uiFont; font.pixelSize: 13; font.weight: Font.Medium
            wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
        }
        Accessible.role: Accessible.AlertMessage; Accessible.name: win.loginError
    }


    // ================= Приветствие: вход и регистрация =================
    FontLoader { id: fontDisplay; source: backend.assets + "fonts/InterDisplay-Black.otf" }
    FontLoader { id: fontMedium; source: backend.assets + "fonts/Inter-Medium.otf" }
    FontLoader { id: fontSemi; source: backend.assets + "fonts/Inter-SemiBold.otf" }
    Timer { id: focusTimer; interval: 90; property var target: null; onTriggered: { if (target) target.forceActiveFocus() } }
    Shortcut { sequence: "Escape"; enabled: win.authVisible && win.authMode !== "welcome"; onActivated: win.showAuth("welcome") }

    Item {
        id: loginPage
        anchors.fill: parent; visible: !win.loggedIn; clip: true
        property real intro: 0
        readonly property real panelW: compact ? Math.min(520, width - 48) : Math.min(1040, width * 0.565)
        readonly property real heroSize: Math.max(136, Math.min(218, width * 0.14, height * 0.30))
        readonly property bool compact: win.authMode !== "welcome"
        NumberAnimation on intro { from: 0; to: 1; duration: 1300; easing.type: Easing.OutCubic }

        // Isolated backdrop avoids sampling the title itself in the glass texture.
        Item {
            id: loginBackdrop
            anchors.fill: parent
            // ---- живой фон: твоя картинка + три «дышащих» световых пятна ----
            Rectangle { anchors.fill: parent; color: "#f7f5fc" }
            Image {
                anchors.fill: parent
                source: backend.assets + "welcome-bg.png"; fillMode: Image.PreserveAspectCrop; smooth: true
                property real breath: 0
                scale: 1.05 + 0.08 * breath
                SequentialAnimation on breath {
                    running: win.authVisible; loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: 15000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 15000; easing.type: Easing.InOutSine }
                }
            }
            Glow { tint: "#79f4ff"; radiusPx: Math.max(loginPage.width, loginPage.height) * 0.30; anchorX: loginPage.width * 0.46; anchorY: loginPage.height * 0.30
                   driftX: 90; driftY: 40; driftMs: 9500; pulseMs: 5200; lo: 0.15; hi: 0.75 }
            Glow { tint: "#b79cff"; radiusPx: Math.max(loginPage.width, loginPage.height) * 0.28; anchorX: loginPage.width * 0.14; anchorY: loginPage.height * 0.80
                   driftX: 60; driftY: 70; driftMs: 11000; pulseMs: 6800; lo: 0.2; hi: 0.8 }
            Glow { tint: "#ffae88"; radiusPx: Math.max(loginPage.width, loginPage.height) * 0.26; anchorX: loginPage.width * 0.90; anchorY: loginPage.height * 0.62
                   driftX: 50; driftY: 80; driftMs: 10000; pulseMs: 4600; lo: 0.15; hi: 0.7 }
        }

        BackChip {
            x: 28; y: 26
            opacity: loginPage.compact ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 250 } }
            onClicked: win.showAuth("welcome")
        }

        ColumnLayout {
            id: stack
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: loginPage.compact ? undefined : parent.top
            anchors.topMargin: loginPage.height * 0.085
            anchors.verticalCenter: loginPage.compact ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: loginPage.compact ? -24 : -8
            // Keep validation messages and the sign-in link above the footer on short screens.
            scale: loginPage.compact ? Math.min(1, (loginPage.height - 140) / Math.max(1, implicitHeight)) : 1
            spacing: 0

            // ---- надпись из макета и зеркальный Focus ----
            Image {
                objectName: "welcomeScript"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: loginPage.compact ? 154 : loginPage.width * 0.165
                Layout.preferredHeight: Layout.preferredWidth * 75 / 295
                Layout.bottomMargin: loginPage.compact ? 8 : 12
                source: backend.assets + "welcome-script.svg"
                sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit; smooth: true
                opacity: loginPage.intro
                Accessible.name: "welcome"
            }
            Item {
                id: focusTitle
                objectName: "glassFocusTitle"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -titleSize * 0.08
                Layout.bottomMargin: -titleSize * 0.14
                implicitWidth: titleGlyph.implicitWidth
                implicitHeight: titleGlyph.implicitHeight
                property real titleSize: Math.round(loginPage.compact ? loginPage.heroSize * 0.5 : loginPage.heroSize)
                property real floaty: 0
                property real shimmer: -0.35
                readonly property point backdropOrigin: {
                    // Track layout, the floating transform and the animated title size.
                    return Qt.point(stack.x + x, stack.y + y + floaty + (1 - loginPage.intro) * 28)
                }
                opacity: loginPage.intro
                transform: Translate { y: (1 - loginPage.intro) * 28 + focusTitle.floaty }
                Behavior on titleSize { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                SequentialAnimation on floaty {
                    running: win.authVisible; loops: Animation.Infinite
                    NumberAnimation { to: -5; duration: 4200; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 5; duration: 4200; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on shimmer {
                    running: win.authVisible; loops: Animation.Infinite
                    NumberAnimation { to: 1.35; duration: 6200; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 2400 }
                    NumberAnimation { to: -0.35; duration: 6200; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 2400 }
                }
                Text {
                    id: titleGlyph
                    text: "Focus"; color: "white"
                    font.family: win.displayFont; font.weight: Font.Black
                    font.pixelSize: focusTitle.titleSize
                    font.letterSpacing: -focusTitle.titleSize * 0.035
                }
                ShaderEffectSource {
                    id: titleMask
                    anchors.fill: parent; visible: false
                    sourceItem: titleGlyph; hideSource: true
                    live: win.authVisible; smooth: true
                }
                ShaderEffectSource {
                    id: titleBackdrop
                    anchors.fill: parent; visible: false
                    sourceItem: loginBackdrop
                    sourceRect: Qt.rect(focusTitle.backdropOrigin.x, focusTitle.backdropOrigin.y,
                                        focusTitle.width, focusTitle.height)
                    live: win.authVisible; smooth: true
                }
                ShaderEffect {
                    anchors.fill: parent
                    property variant glyphMask: titleMask
                    property variant backdrop: titleBackdrop
                    property size effectSize: Qt.size(width, height)
                    property real shimmer: focusTitle.shimmer
                    fragmentShader: "qrc:/focus/shaders/glass-title.frag.qsb"
                }
                Accessible.role: Accessible.StaticText
                Accessible.name: "Focus"
            }

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                implicitWidth: modeLabel.implicitWidth
                implicitHeight: loginPage.compact ? modeLabel.implicitHeight + 6 : 0
                Behavior on implicitHeight { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                Text {
                    id: modeLabel
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.authMode === "register" ? "Создание аккаунта" : "Вход в аккаунт"
                    color: "#4d4d62"; font.family: win.uiFont; font.pixelSize: 18; font.weight: Font.Medium
                    opacity: loginPage.compact ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }
            }
            Item {
                implicitHeight: loginPage.compact ? 18 : loginPage.height * 0.060
                Behavior on implicitHeight { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            }

            // ---- рабочая область: выбор / вход / регистрация ----
            Item {
                id: formArea
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: loginPage.panelW
                implicitHeight: win.authMode === "login" ? loginPanel.implicitHeight
                              : (win.authMode === "register" ? registerPanel.implicitHeight : welcomePanel.implicitHeight)
                Behavior on implicitHeight { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                opacity: Math.min(1, Math.max(0, (loginPage.intro - 0.35) / 0.65))

                // 1. выбор: войти или зарегистрироваться
                ColumnLayout {
                    id: welcomePanel
                    readonly property bool shown: win.authMode === "welcome"
                    width: parent.width; spacing: 14
                    opacity: shown ? 1 : 0; visible: shown || opacity > 0.01; enabled: shown
                    Behavior on opacity { NumberAnimation { duration: welcomePanel.shown ? 300 : 120 } }
                    transform: Translate { y: welcomePanel.shown ? 0 : 16; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
                    ChoiceBar { objectName: "chooseLogin"; Layout.fillWidth: true; glyph: "→"; title: "Войти"; subtitle: "У меня уже есть аккаунт"; onClicked: win.showAuth("login") }
                    ChoiceBar { objectName: "chooseRegister"; Layout.fillWidth: true; glyph: "+"; title: "Регистрация"; subtitle: "Создать новый аккаунт"; onClicked: win.showAuth("register") }
                }

                // 2. вход
                ColumnLayout {
                    id: loginPanel
                    readonly property bool shown: win.authMode === "login"
                    width: parent.width; spacing: 12
                    opacity: shown ? 1 : 0; visible: shown || opacity > 0.01; enabled: shown
                    Behavior on opacity { NumberAnimation { duration: loginPanel.shown ? 300 : 120 } }
                    transform: Translate { y: loginPanel.shown ? 0 : 16; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
                    GlassInput { id: username; objectName: "username"; Layout.fillWidth: true; placeholder: "Логин"; onAccepted: password.input.forceActiveFocus() }
                    GlassInput { id: password; objectName: "password"; Layout.fillWidth: true; placeholder: "Пароль"; secret: true; onAccepted: win.login() }
                    ErrorPill { Layout.fillWidth: true }
                    PrimaryButton {
                        id: loginBtn; objectName: "loginButton"
                        Layout.fillWidth: true; Layout.topMargin: 4
                        text: win.loginBusy ? "Входим…" : "Войти в Focus"
                        enabled: backend.ready && !win.loginBusy
                        onClicked: win.login()
                    }
                    LinkText { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 4; lead: "Нет аккаунта?"; action: "Зарегистрироваться"; onClicked: win.showAuth("register") }
                    LinkText { Layout.alignment: Qt.AlignHCenter; lead: "Демо-доступ:"; action: "arina · 1234"; onClicked: { username.text = "arina"; password.text = "1234"; win.loginError = "" } }
                }

                // 3. регистрация
                ColumnLayout {
                    id: registerPanel
                    readonly property bool shown: win.authMode === "register"
                    width: parent.width; spacing: 12
                    opacity: shown ? 1 : 0; visible: shown || opacity > 0.01; enabled: shown
                    Behavior on opacity { NumberAnimation { duration: registerPanel.shown ? 300 : 120 } }
                    transform: Translate { y: registerPanel.shown ? 0 : 16; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
                    GlassInput { id: regName; objectName: "regName"; Layout.fillWidth: true; placeholder: "Ваше имя"; onAccepted: regUser.input.forceActiveFocus() }
                    GlassInput { id: regUser; objectName: "regUser"; Layout.fillWidth: true; placeholder: "Логин (латиницей)"; onAccepted: regPass.input.forceActiveFocus() }
                    GlassInput { id: regPass; objectName: "regPass"; Layout.fillWidth: true; placeholder: "Пароль — от 8 символов"; secret: true; onAccepted: regPass2.input.forceActiveFocus() }
                    Item {
                        Layout.fillWidth: true; implicitHeight: 18
                        visible: regPass.text.length > 0
                        RowLayout {
                            anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            Repeater {
                                model: 3
                                Rectangle {
                                    required property int index
                                    Layout.preferredWidth: 30; Layout.preferredHeight: 5; Layout.alignment: Qt.AlignVCenter
                                    radius: 2.5
                                    color: index < win.passwordScore(regPass.text) ? win.strengthColor(win.passwordScore(regPass.text)) : "#26000000"
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                            Text {
                                Layout.leftMargin: 6; Layout.alignment: Qt.AlignVCenter
                                text: win.strengthText(regPass.text)
                                color: win.passwordScore(regPass.text) === 0 ? "#c14332" : "#6d6d80"
                                font.family: win.uiFont; font.pixelSize: 12; font.weight: Font.Medium
                            }
                        }
                    }
                    GlassInput { id: regPass2; objectName: "regPass2"; Layout.fillWidth: true; placeholder: "Повторите пароль"; secret: true; onAccepted: win.signUp() }
                    ErrorPill { Layout.fillWidth: true }
                    PrimaryButton {
                        id: registerBtn; objectName: "registerButton"
                        Layout.fillWidth: true; Layout.topMargin: 4
                        text: win.loginBusy ? "Создаём аккаунт…" : "Создать аккаунт"
                        enabled: backend.ready && !win.loginBusy
                        onClicked: win.signUp()
                    }
                    LinkText { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 4; lead: "Уже есть аккаунт?"; action: "Войти"; onClicked: win.showAuth("login") }
                }
            }
        }

        // ---- состояние сервера и пометка демо ----
        ColumnLayout {
            anchors { bottom: parent.bottom; bottomMargin: 22; horizontalCenter: parent.horizontalCenter }
            spacing: 4
            opacity: loginPage.intro
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 8
                Rectangle {
                    id: statusDot
                    Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4
                    color: backend.ready ? "#34c759" : "#ff9f0a"
                    property real pulse: 1
                    opacity: backend.ready ? 1 : pulse
                    SequentialAnimation on pulse {
                        running: win.authVisible && !backend.ready; loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 700 }
                        NumberAnimation { to: 1; duration: 700 }
                    }
                }
                Text { text: backend.status; visible: text.length > 0; color: "#6d6d80"; font.family: win.uiFont; font.pixelSize: 12 }
            }
            LinkText { Layout.alignment: Qt.AlignHCenter; visible: !backend.ready; action: "Повторить запуск"; onClicked: backend.restart() }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Демонстрационная версия · Только тестовые данные"
                color: "#9a9aae"; font.family: win.uiFont; font.pixelSize: 11
            }
        }
    }
    Item {
        id: shell
        anchors.fill: parent; visible: win.loggedIn; clip: true

        Image { anchors.fill: parent; source: backend.assets + "workspace-bg.svg"; fillMode: Image.Stretch }
        Rectangle { anchors.fill: parent; color: "#cc14161c"; visible: backend.dark }

        // ---------- левые «язычки»-инструменты ----------
        Flickable {
            id: toolsFlick
            x: 16; y: 114; width: 222; height: shell.height - 130; z: 2
            clip: true; contentWidth: width; contentHeight: toolsCol.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
            Column {
                id: toolsCol
                spacing: 3
                Repeater {
                    model: ["home"].concat(win.sideFeatures)
                    delegate: Item {
                        id: tool
                        objectName: modelData === "home" ? "feature-home" : "feature-" + modelData
                        required property string modelData
                        readonly property var feat: win.sections[modelData]
                        readonly property string featureKey: feat.feature
                        readonly property bool active: toolHover.hovered || win.page === modelData
                        width: 202; height: 42
                        scale: toolHover.hovered ? 1.055 : 1; transformOrigin: Item.Left
                        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                        Rectangle {
                            width: 200; height: 42; radius: 21
                            x: 2
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            color: backend.dark ? (tool.active ? "#593a3d49" : "#382a2c33") : (tool.active ? "#e9ffffff" : "#b3ffffff")
                            border.width: 1; border.color: tool.active ? "#ddffffff" : "#80ffffff"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Row {
                                x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 9
                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    color: backend.dark ? "#28ffffff" : "#b3ffffff"
                                    Image { anchors.centerIn: parent; width: 18; height: 18; source: backend.assets + "icons/" + tool.feat.icon + ".svg"; smooth: true }
                                }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: tool.feat.title; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.ink; width: 126; elide: Text.ElideRight }
                            }
                        }
                        HoverHandler { id: toolHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.navigate(tool.modelData) }
                        DragHandler {
                            id: toolDrag
                            target: null
                            enabled: tool.modelData !== "home"
                            onActiveChanged: {
                                if (active) tool.Drag.startDrag(Qt.CopyAction)
                                else tool.Drag.drop()
                            }
                        }
                        Drag.active: toolDrag.active
                        Drag.source: tool
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2
                        Drag.dragType: Drag.None
                        Drag.keys: ["focus-feature"]
                        Drag.supportedActions: Qt.CopyAction
                        Drag.mimeData: ({"text/plain": tool.featureKey})
                        ToolTip.visible: toolHover.hovered; ToolTip.text: feat.title; ToolTip.delay: 600
                        Accessible.role: Accessible.Button; Accessible.name: feat.title
                    }
                }
            }
        }

        // ---------- компактный док: четыре перетаскиваемые функции ----------
        Item {
            id: topTab
            anchors.horizontalCenter: parent.horizontalCenter; y: 40; z: 3
            width: topRow.implicitWidth + 48; height: 56
            Rectangle {
                anchors.fill: parent; radius: 35
                color: backend.dark ? "#d9262830" : "#c9f5f3fb"
                border.color: "#d9ffffff"; border.width: 1.2
                Rectangle { anchors { fill: parent; margins: 5 } radius: 30; color: "#26ffffff" }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#333e3b54"; shadowBlur: 0.55; shadowVerticalOffset: 4; shadowOpacity: 0.24 }
            }
            Row {
                id: topRow
                anchors.centerIn: parent
                spacing: 24
                Repeater {
                    model: 4
                    delegate: Item {
                        id: dockSlot
                        objectName: "pin-slot-" + index
                        required property int index
                        readonly property string featureKey: index < win.pinnedFeatures.length ? win.pinnedFeatures[index] : ""
                        readonly property var feature: featureKey.length ? win.features[featureKey] : null
                        width: 76; height: 38
                        scale: dockDrop.containsDrag ? 1.035 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: 25
                            color: dockDrop.containsDrag ? "#eaffffff" : (dockMouse.containsMouse ? "#ecffffff" : "#aaffffff")
                            border.width: dockDrop.containsDrag ? 2 : 1
                            border.color: dockDrop.containsDrag ? win.accent : "#e6ffffff"
                            Behavior on color { ColorAnimation { duration: 130 } }
                            Image {
                                anchors.centerIn: parent; width: 20; height: 20
                                visible: !!dockSlot.feature
                                source: dockSlot.feature ? backend.assets + "icons/" + dockSlot.featureKey + ".svg" : ""
                            }
                            Text { anchors.centerIn: parent; visible: !dockSlot.feature; text: "+"; font.pixelSize: 22; color: "#655d86" }

                        }
                        MouseArea {
                            id: dockMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: dockSlot.feature ? win.openFeature(dockSlot.featureKey) : win.showPinPicker(dockSlot.index)
                            onPressAndHold: if (dockSlot.feature) win.unpinFeature(dockSlot.index)
                        }
                        DropArea {
                            id: dockDrop
                            anchors.fill: parent; keys: ["focus-feature"]
                            onDropped: function(drop) {
                                const key = drop.source ? (drop.source.featureKey || drop.source.modelData) : ""
                                if (win.features[key]) { win.pinFeature(dockSlot.index, key); drop.acceptProposedAction() }
                            }
                        }
                        ToolTip.visible: dockMouse.containsMouse
                        ToolTip.text: dockSlot.feature ? dockSlot.feature.sub + "\nПеретащите функцию сюда, чтобы заменить; удерживайте, чтобы убрать." : "Перетащите функцию слева или нажмите, чтобы выбрать."
                        ToolTip.delay: 350
                        Accessible.role: Accessible.Button
                        Accessible.name: dockSlot.feature ? dockSlot.feature.title : "Добавить функцию"
                    }
                }
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: 28; top: parent.top; topMargin: 44 } spacing: 10; z: 3
            RoundBtn { size: 40; icon: "notifications"; Accessible.name: "Уведомления"; onClicked: win.openUtility("notifications") }
            RoundBtn { size: 40; icon: "settings"; Accessible.name: "Настройки"; onClicked: win.navigate("settings") }
            RoundBtn { size: 40; icon: "logout"; Accessible.name: "Выйти"; onClicked: win.logout() }
        }

        // ---------- центральная область ----------
        Item {
            id: contentArea
            anchors {
                left: parent.left; leftMargin: 232; top: parent.top; bottom: parent.bottom; bottomMargin: 20
                right: parent.right; rightMargin: 20
            }
            Loader { id: homeLoader; anchors.fill: parent; active: win.page === "home"; sourceComponent: homeView }
            Rectangle {
                anchors { fill: parent; topMargin: 118 } visible: win.page !== "home" && win.page !== "chat"; radius: 34
                color: win.glassSoft; border.color: win.glassEdge; border.width: 1.5
                ScrollView {
                    id: pageScroll
                    anchors.fill: parent; anchors.margins: 6; clip: true; contentWidth: availableWidth
                    ColumnLayout {
                        width: pageScroll.availableWidth; spacing: 24
                        Loader {
                            id: workspaceLoader
                            Layout.fillWidth: true; Layout.margins: 28
                            active: win.loggedIn && win.page !== "home" && win.page !== "chat"
                            sourceComponent: workspaceView
                        }
                        Hint { text: "FOCUS · ДЕМОНСТРАЦИОННАЯ ВЕРСИЯ"; font.pixelSize: 10; font.letterSpacing: 1; Layout.leftMargin: 34; Layout.bottomMargin: 24 }
                    }
                }
            }
            Rectangle {
                visible: !backend.ready; z: 3; anchors { top: parent.top; topMargin: 112; left: parent.left; right: parent.right } height: 54; radius: 27; color: win.soft; border.color: win.glassEdge
                RowLayout { anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 6; anchors.topMargin: 6; anchors.bottomMargin: 6; Copy { text: backend.status; Layout.fillWidth: true } Action { text: "Повторить запуск"; onClicked: backend.restart() } }
            }
        }
    }
    Component {
        id: homeView
        Item {
            id: home
            property alias searchText: homeQueryField.text
            Text {
                id: welcomeWord
                objectName: "homeWelcomeWord"
                height: home.height * 0.27
                width: Math.max(0, home.width - 460)
                x: 0
                anchors.top: parent.top; anchors.topMargin: Math.max(96, home.height * 0.16)
                text: "Welcome"
                font.family: "Segoe Script"; font.pixelSize: Math.min(140, Math.max(48, width * 0.17)); fontSizeMode: Text.Fit; minimumPixelSize: 36; maximumLineCount: 1; clip: true
                font.weight: Font.Normal; color: "#78ffffff"
                opacity: 0.88; horizontalAlignment: Text.AlignHCenter
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#55ffffff"; shadowBlur: 0.25; shadowVerticalOffset: 1; shadowOpacity: 0.22 }
            }

            Panel {
                id: homeSearchBar
                width: Math.min(900, Math.max(260, home.width - (win.chatOpen ? 460 : 238)))
                height: homeAttachedFileName.length ? 84 : 60
                x: 16
                anchors.top: welcomeWord.bottom; anchors.topMargin: 26
                radius: 36
                RowLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 8; leftMargin: 10; rightMargin: 10 }
                    height: 44; spacing: 10
                    RoundBtn {
                        size: 44; icon: "attach"
                        Accessible.name: "Прикрепить документ"
                        onClicked: homeFileDialog.open()
                    }
                    Field {
                        id: homeQueryField; objectName: "homeQuery"; Layout.fillWidth: true; maximumLength: 11000
                        background: null; font.pixelSize: 14; leftPadding: 8
                        text: win.homeQueryText
                        onTextChanged: if (text !== win.homeQueryText) win.homeQueryText = text
                        placeholderText: homeAttachedFileName ? "Вопрос по файлу: " + homeAttachedFileName : "Спросите что угодно…"
                        onAccepted: win.sendHomePrompt()
                    }
                    RoundBtn {
                        size: 44; icon: "send"
                        enabled: backend.ready && !win.homeSearchBusy && !win.chatBusy
                        Accessible.name: "Отправить запрос"
                        onClicked: win.sendHomePrompt()
                    }
                }
                Hint {
                    visible: homeAttachedFileName.length > 0
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 74; bottomMargin: 6 }
                    text: "Файл будет добавлен в библиотеку: " + homeAttachedFileName
                    font.pixelSize: 10; elide: Text.ElideMiddle
                }
            }

            // Плавающий календарь: перетаскивайте за точку в заголовке, сверните стрелкой.
            Panel {
                id: cal
                property int m: new Date().getMonth()
                property int calendarYear: new Date().getFullYear()
                property int selectedDay: new Date().getDate()
                property int selectedMonth: new Date().getMonth()
                property int selectedYear: new Date().getFullYear()
                readonly property var months: ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"]
                x: 18; y: home.height - height - 42
                width: 252; height: win.calendarCollapsed ? 48 : 236; radius: 28; clip: true; z: 2
                Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 6
                    RowLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: 34; spacing: 7
                        Item {
                            width: 22; height: 30
                            Text { anchors.centerIn: parent; text: "⠿"; font.pixelSize: 18; color: win.muted }
                            DragHandler {
                                target: cal
                                xAxis.minimum: 0; xAxis.maximum: Math.max(0, home.width - cal.width)
                                yAxis.minimum: 90; yAxis.maximum: Math.max(90, home.height - cal.height)
                            }
                            HoverHandler { id: dragHandleHover; cursorShape: Qt.SizeAllCursor }
                            ToolTip.visible: dragHandleHover.hovered; ToolTip.text: "Перетащите календарь"; ToolTip.delay: 400
                        }
                        Copy {
                            Layout.fillWidth: true
                            text: win.calendarCollapsed
                                ? cal.selectedDay + " " + cal.months[cal.selectedMonth].toLowerCase()
                                : cal.months[cal.m] + " " + cal.calendarYear
                            font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        RoundBtn {
                            size: 28; glyph: "‹"; visible: !win.calendarCollapsed
                            onClicked: { if (cal.m === 0) { cal.m = 11; cal.calendarYear-- } else cal.m-- }
                        }
                        RoundBtn {
                            size: 28; glyph: win.calendarCollapsed ? "⌄" : "⌃"
                            Accessible.name: win.calendarCollapsed ? "Развернуть календарь" : "Свернуть календарь"
                            onClicked: win.calendarCollapsed = !win.calendarCollapsed
                        }
                        RoundBtn {
                            size: 28; glyph: "›"; visible: !win.calendarCollapsed
                            onClicked: { if (cal.m === 11) { cal.m = 0; cal.calendarYear++ } else cal.m++ }
                        }
                    }
                    DayOfWeekRow {
                        visible: !win.calendarCollapsed; Layout.fillWidth: true; locale: Qt.locale("ru_RU")
                        delegate: Text { required property var model; text: model.shortName.toUpperCase(); horizontalAlignment: Text.AlignHCenter; font.pixelSize: 9; font.weight: Font.DemiBold; color: win.muted }
                    }
                    MonthGrid {
                        id: grid
                        visible: !win.calendarCollapsed
                        Layout.fillWidth: true; Layout.fillHeight: true
                        month: cal.m; year: cal.calendarYear; locale: Qt.locale("ru_RU")
                        delegate: Item {
                            id: dayCell
                            required property var model
                            Rectangle {
                                anchors.centerIn: parent; width: 28; height: 28; radius: 14
                                color: dayCell.model.day === cal.selectedDay && dayCell.model.month === cal.selectedMonth && dayCell.model.year === cal.selectedYear ? win.accent : "transparent"
                            }
                            Text {
                                anchors.centerIn: parent; text: dayCell.model.day; font.pixelSize: 12
                                font.weight: dayCell.model.today || (dayCell.model.day === cal.selectedDay && dayCell.model.month === cal.selectedMonth && dayCell.model.year === cal.selectedYear) ? Font.Bold : Font.Normal
                                color: dayCell.model.day === cal.selectedDay && dayCell.model.month === cal.selectedMonth && dayCell.model.year === cal.selectedYear ? "white" : win.ink
                                opacity: dayCell.model.month === grid.month ? 1 : 0.28
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    cal.selectedDay = dayCell.model.day
                                    cal.selectedMonth = dayCell.model.month
                                    cal.selectedYear = dayCell.model.year
                                    cal.m = dayCell.model.month
                                    cal.calendarYear = dayCell.model.year
                                }
                            }
                        }
                    }
                }
            }

            Panel {
                x: 288; y: cal.y; width: Math.max(260, home.width - 528); height: 236
                visible: home.width > 850 && !win.chatOpen
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 18; spacing: 12
                    RowLayout { Layout.fillWidth: true; Copy { text: "Рабочий обзор"; font.weight: Font.DemiBold; Layout.fillWidth: true } Action { text: "Аналитика →"; implicitHeight: 28; onClicked: win.navigate("analytics") } }
                    RowLayout {
                        Layout.fillWidth: true
                        Repeater { model: [{title:"Поручения",value:(win.dashboardData.metrics || {}).tasks || 0},{title:"Готово",value:(win.dashboardData.metrics || {}).completed || 0},{title:"Документы",value:(win.dashboardData.metrics || {}).documents || 0}]; delegate: ColumnLayout { required property var modelData; Layout.fillWidth: true; Copy { text: modelData.value; font.pixelSize: 25; font.weight: Font.DemiBold } Hint { text: modelData.title; font.pixelSize: 10 } } }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.line }
                    Hint { text: "Ближайшие поручения"; Layout.fillWidth: true }
                    Repeater { model: (win.dashboardData.tasks || []).slice(0,2); delegate: Copy { required property var modelData; text: "• " + modelData.title; Layout.fillWidth: true; font.pixelSize: 11; maximumLineCount: 1; elide: Text.ElideRight } }
                    Item { Layout.fillHeight: true }
                }
            }

            // Небольшой выбор четырёх агентов; клик открывает отдельное окно диалога.
            Panel {
                id: assist
                visible: !win.chatOpen
                width: 208; height: 268
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter; verticalCenterOffset: 12 }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 9
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: 28; height: 28; radius: 14; color: "#dce6f1"
                            Text { anchors.centerIn: parent; text: "✦"; color: win.ink; font.pixelSize: 15 }
                        }
                        Copy { text: "Ваш агент"; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Hint { text: "↗"; font.pixelSize: 15 }
                    }
                    GridLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 190; columns: 2; rowSpacing: 7; columnSpacing: 7
                        Repeater {
                            model: win.agents
                            delegate: Item {
                                id: agentTile
                                required property var modelData
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Rectangle {
                                    anchors.fill: parent; radius: 20
                                    color: agentTileMouse.containsMouse ? "#40ffffff" : "transparent"
                                    border.width: 0
                                    border.color: agentTile.modelData.key === win.agent ? win.accent : "#80ffffff"
                                    Behavior on color { ColorAnimation { duration: 130 } }
                                }
                                AvatarPortrait {
                                    anchors { fill: parent; margins: 1 }
                                    portraitIndex: agentTile.modelData.portrait
                                }

                                MouseArea {
                                    id: agentTileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onEntered: win.hoverAgent = agentTile.modelData.key
                                    onExited: win.hoverAgent = ""
                                    onClicked: win.openAgent(agentTile.modelData.key)
                                }
                                ToolTip.visible: agentTileMouse.containsMouse
                                ToolTip.text: agentTile.modelData.name + " · " + agentTile.modelData.area + "\n" + agentTile.modelData.description
                                ToolTip.delay: 300
                                Accessible.role: Accessible.Button; Accessible.name: agentTile.modelData.name + ": " + agentTile.modelData.description
                            }
                        }
                    }

                }
            }
        }
    }
    Component {
        id: workspaceView
        WorkspacePage {
            section: win.page; api: function(path,body) { return body === undefined ? win.api(path) : win.api(path,body) }
            revision: win.workspaceRevision; dark: backend.dark; recording: backend.recording; savedKey: backend.keySaved
            onCreateTask: function(title) { win.newTask(title) }
            onCreateMeeting: win.newMeeting()
            onCreateDocument: { win.loadDocuments(); win.newDocument() }
            onImportDocument: documentFileDialog.open()
            onTaskStatusRequested: function(record,status) {
                if (record.demo) { win.api("/workspace/action",{action:"move_demo_task",id:record.id,status:status}).then(function() { win.workspaceRevision++ }).catch(function(e) { win.toast(e.message) }); return }
                const raw = record.raw; const value = JSON.parse(JSON.stringify(raw.data)); value.status = status
                win.prepare("update_object",{id:raw.id,version:raw.version,data:value},"Изменить статус поручения «" + raw.title + "» → " + status,"tasks")
            }
            onDocumentDecision: function(record,status) {
                const raw = record.raw; const value = JSON.parse(JSON.stringify(raw.data)); value.approval_status = status
                const events = value.approval_history || []; value.approval_history = events.concat([{at:new Date().toISOString(),status:status,by:win.userName}])
                win.prepare("update_object",{id:raw.id,version:raw.version,data:value},"Документ «" + raw.title + "»: " + status,"documents")
            }
            onOpenDocument: function(ident) { win.openDocument(ident) }
            onComposeMessage: function(recipient,title,body) { win.prepare("send_message",{recipient:recipient,title:title,body:body},"Кому: " + recipient + "\nТема: " + title + "\n\n" + body + "\n\nПосле подтверждения письмо сохранится в тестовом шлюзе.","mail") }
            onExportRequested: function(format,title,rows) { win.exportKind = format; win.exportTitle = title; win.exportRows = rows; reportSaveDialog.open() }
            onConnectionRequested: aiDialog.open()
            onThemeRequested: function(value) { backend.dark = value }
            onRecordRequested: function(start) { if (start) backend.startMeetingRecording(); else backend.stopMeetingRecording() }
            onChatRequested: function(text) { win.navigate("chat"); prompt.text = text; win.sendPrompt() }
        }
    }
    FileDialog {
        id: reportSaveDialog; fileMode: FileDialog.SaveFile; defaultSuffix: win.exportKind
        nameFilters: win.exportKind === "pdf" ? ["PDF (*.pdf)"] : ["Excel (*.xlsx)"]
        title: "Сохранить отчёт Focus"
        onAccepted: {
            const file = selectedFile
            if (win.exportKind === "pdf") { if (backend.exportPdf(file,win.exportTitle,win.exportRows)) win.toast("PDF сохранён"); else win.toast("Не удалось сохранить PDF") }
            else win.api("/workspace/export",{title:win.exportTitle,rows:win.exportRows}).then(function(value) { if (backend.saveArtifact(file,value.content)) win.toast("Excel сохранён"); else win.toast("Не удалось сохранить Excel") }).catch(function(e) { win.toast(e.message) })
        }
    }
    Component {
        id: tasksView
        ColumnLayout {
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout { spacing: 5
                    Hint { text: "ПОРУЧЕНИЯ И СРОКИ"; color: win.accent; font.letterSpacing: 1 }
                    Copy { text: "Задачи"; font.pixelSize: 32; font.bold: true }
                    Hint { text: win.records.length + " задач в доступной вам области" }
                }
                Item { Layout.fillWidth: true }
                Action { text: "＋ Создать задачу"; primary: true; onClicked: win.newTask("") }
            }
            BusyIndicator { running: win.loading; visible: running }
            Copy { text: win.pageError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            Hint { text: "Пока нет задач. Создайте поручение, чтобы начать работу."; visible: !win.loading && !win.pageError && !win.records.length }
            Repeater {
                model: win.records
                delegate: Panel {
                    id: taskCard
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: taskColumn.implicitHeight + 42
                    ColumnLayout {
                        id: taskColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 } spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            Copy { text: taskCard.modelData.title; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                            Hint { text: ((taskCard.modelData.data || {}).status || "без статуса"); color: win.accent }
                        }
                        Hint { text: "Срок: " + win.formatDate((taskCard.modelData.data || {}).due); Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Hint { text: "Запись №" + taskCard.modelData.id; Layout.fillWidth: true }
                            Action {
                                property var taskState: taskCard.modelData.data || ({})
                                property bool done: ["завершена","done","completed","выполнена"].indexOf(String(taskState.status || "").toLowerCase()) >= 0
                                text: done ? "Вернуть в работу" : "Отметить выполненной"
                                onClicked: win.toggleTask(taskCard.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: meetingsView
        ColumnLayout {
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout { spacing: 5
                    Hint { text: "РАСПИСАНИЕ И ПОВЕСТКИ"; color: "#6082a5"; font.letterSpacing: 1 }
                    Copy { text: "Встречи"; font.pixelSize: 32; font.bold: true }
                    Hint { text: "Тестовый календарь · создавайте и просматривайте встречи" }
                }
                Item { Layout.fillWidth: true }
                Action { text: "＋ Новая встреча"; primary: true; onClicked: win.newMeeting() }
            }
            BusyIndicator { running: win.loading; visible: running }
            Copy { text: win.pageError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            Hint { text: "Встреч пока нет. Добавьте встречу с датой, временем и повесткой."; visible: !win.loading && !win.pageError && !win.records.length }
            Repeater {
                model: win.records
                delegate: Panel {
                    id: meetingCard
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: meetingColumn.implicitHeight + 42
                    ColumnLayout {
                        id: meetingColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 } spacing: 9
                        Hint { text: win.formatDate((meetingCard.modelData.data || {}).start); color: "#6082a5"; font.weight: Font.DemiBold }
                        Copy { text: meetingCard.modelData.title; font.pixelSize: 18; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Hint { text: "До: " + win.formatDate((meetingCard.modelData.data || {}).end); Layout.fillWidth: true }
                        Copy { text: (meetingCard.modelData.data || {}).agenda || "Повестка пока не указана"; Layout.fillWidth: true }
                        Hint { text: "Участники: " + (((meetingCard.modelData.data || {}).participants || []).length || 1) }
                    }
                }
            }
        }
    }
    Component {
        id: documentsView
        ColumnLayout {
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout { spacing: 5
                    Hint { text: "БИБЛИОТЕКА РАБОЧИХ МАТЕРИАЛОВ"; color: "#66818a"; font.letterSpacing: 1 }
                    Copy { text: "Документы"; font.pixelSize: 32; font.bold: true }
                    Hint { text: win.records.length + " доступных документов · личные файлы сохраняются в вашей папке Focus" }
                }
                Item { Layout.fillWidth: true }
                Action { text: "＋ Папка"; onClicked: win.newFolder() }
                Action { text: "＋ Документ"; primary: true; onClicked: win.newDocument() }
            }
            Panel {
                Layout.fillWidth: true; implicitHeight: 116
                ColumnLayout { anchors.fill: parent; anchors.margins: 18; spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        ComboBox {
                            id: libraryFolderBox
                            Layout.preferredWidth: 210
                            model: win.folderNames()
                            currentIndex: win.selectedFolderId < 0 ? 0 : Math.max(0, win.folderIndex(win.selectedFolderId) + 1)
                            onActivated: win.loadDocuments(currentIndex === 0 ? -1 : win.folders[currentIndex - 1].id)
                        }
                        Field { id: documentSearchField; Layout.fillWidth: true; placeholderText: "Поиск по названию и содержимому…"; text: win.documentSearchText; onAccepted: win.searchDocuments(text) }
                        Action { text: "Найти"; onClicked: win.searchDocuments(documentSearchField.text) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Hint { text: win.selectedFolderId < 0 ? "Все папки" : "Папка: " + win.folderName(win.selectedFolderId); Layout.fillWidth: true }
                        Action { text: "Импортировать файл…"; onClicked: documentFileDialog.open() }
                        Hint { text: "TXT · MD · CSV · JSON · DOCX · PDF"; font.pixelSize: 10 }
                    }
                }
            }
            BusyIndicator { running: win.loading; visible: running }
            Copy { text: win.pageError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            Hint { text: "Здесь пока пусто. Создайте текстовый документ или импортируйте один файл."; visible: !win.loading && !win.pageError && !win.records.length }
            Repeater {
                model: win.records
                delegate: Panel {
                    id: documentCard
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: documentColumn.implicitHeight + 38
                    ColumnLayout {
                        id: documentColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Copy { text: documentCard.modelData.title; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                            Action { text: "Читать"; primary: true; onClicked: win.openDocument(documentCard.modelData.id) }
                        }
                        Hint {
                            Layout.fillWidth: true
                            text: "Папка: " + win.folderName((documentCard.modelData.data || {}).folder_id)
                                + " · " + String((documentCard.modelData.data || {}).format || "документ").toUpperCase()
                                + " · обновлён " + win.formatDate(documentCard.modelData.updated)
                        }
                        Hint { text: documentCard.modelData.fragment || ((documentCard.modelData.data || {}).text || "").slice(0, 240); Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
        }
    }
    Component {
        id: analyticsView
        ColumnLayout {
            spacing: 16
            Hint { text: "СВОДКА ПО ДОСТУПНЫМ ДАННЫМ"; color: win.accent; font.letterSpacing: 1 }
            RowLayout {
                Layout.fillWidth: true
                Copy { text: "Обзор"; font.pixelSize: 32; font.bold: true; Layout.fillWidth: true }
                Action { text: "Обновить показатели"; onClicked: win.navigate("analytics") }
            }
            Hint { text: "Метрики рассчитаны по тестовой базе. Формула и источник видны в каждой карточке."; Layout.fillWidth: true }
            BusyIndicator { running: win.loading; visible: running }
            Copy { text: win.pageError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            Repeater {
                model: win.metrics
                delegate: Panel {
                    id: kpiCard
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: kpiColumn.implicitHeight + 44
                    ColumnLayout {
                        id: kpiColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 } spacing: 9
                        RowLayout {
                            Layout.fillWidth: true
                            Copy {
                                text: ({"KPI-01":"Просроченные задачи","KPI-02":"Задачи без владельца","KPI-04":"Просроченные согласования"})[kpiCard.modelData.id] || kpiCard.modelData.id
                                font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true
                            }
                            Copy { text: kpiCard.modelData.value === null ? "Нет данных" : kpiCard.modelData.value + " " + kpiCard.modelData.unit; font.pixelSize: 24; font.bold: true; color: win.accent }
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 7; radius: 4; color: win.soft
                            Rectangle {
                                width: parent.width * (kpiCard.modelData.value === null ? 0 : Math.max(0.04, Math.min(1, Number(kpiCard.modelData.value) / 100)))
                                height: parent.height; radius: 4; color: "#7e9f88"
                            }
                        }
                        Hint { text: kpiCard.modelData.formula; Layout.fillWidth: true }
                        Hint { text: "Источник: " + kpiCard.modelData.source + " · " + kpiCard.modelData.id; Layout.fillWidth: true }
                    }
                }
            }
            Hint { text: "Актуальность: " + (win.metrics.length ? "обновлено при открытии страницы" : "нет данных"); visible: !win.loading }
        }
    }
    Component {
        id: contentView
        ColumnLayout {
            spacing: 16
            Hint { text: "ВАШЕ РАБОЧЕЕ ПРОСТРАНСТВО"; color: win.accent; font.letterSpacing: 1 }
            Copy { text: win.pageTitles[win.page]; font.pixelSize: 32; font.bold: true }
            Hint { text: "Показаны доступные вашей роли тестовые записи." }
            RowLayout {
                Action { visible: win.page === "tasks"; text: "＋ Создать задачу"; primary: true; onClicked: win.newTask("") }
                Field { id: search; visible: win.page === "documents"; Layout.fillWidth: true; placeholderText: "Найти текст в документах…"; onAccepted: win.searchDocuments(text) }
                Action { visible: win.page === "documents"; text: "Найти"; onClicked: win.searchDocuments(search.text) }
                Action { text: "Обновить"; onClicked: win.navigate(win.page) }
            }
            BusyIndicator { running: win.loading; visible: running }
            Copy { text: win.pageError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            Hint { text: "Пока нет доступных записей."; visible: !win.loading && !win.pageError && !win.records.length && win.page !== "analytics" }
            Repeater {
                model: win.records
                delegate: Panel {
                    id: recordPanel
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: recordColumn.implicitHeight + 40
                    ColumnLayout {
                        id: recordColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 } spacing: 10
                        Copy { text: recordPanel.modelData.title; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Hint {
                            Layout.fillWidth: true
                            text: win.page === "tasks" ? "Статус: " + ((recordPanel.modelData.data || {}).status || "не указан") + "  ·  Срок: " + win.formatDate((recordPanel.modelData.data || {}).due)
                                : win.page === "meetings" ? "Начало: " + win.formatDate((recordPanel.modelData.data || {}).start) + "  ·  Конец: " + win.formatDate((recordPanel.modelData.data || {}).end)
                                : "Источник №" + recordPanel.modelData.id
                        }
                        Hint { visible: win.page === "meetings"; text: (recordPanel.modelData.data || {}).agenda || ""; Layout.fillWidth: true }
                        Action {
                            visible: win.page === "documents"; text: "Открыть документ"
                            onClicked: win.api("/objects/" + recordPanel.modelData.id).then(function(data) { detailDialog.title = data.object.title; detailText.text = data.object.data.text || "Текст недоступен"; detailDialog.open() }).catch(function(error) { win.toast(error.message) })
                        }
                    }
                }
            }
            Repeater {
                model: win.metrics
                delegate: Panel {
                    id: metricPanel
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: metricColumn.implicitHeight + 40
                    ColumnLayout {
                        id: metricColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 } spacing: 8
                        Copy { text: ({"KPI-01":"Просроченные задачи","KPI-02":"Задачи без владельца","KPI-04":"Просроченные согласования"})[metricPanel.modelData.id] || metricPanel.modelData.id; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true }
                        Copy { text: metricPanel.modelData.value === null ? "Нет данных" : metricPanel.modelData.value + " " + metricPanel.modelData.unit; font.pixelSize: 30; color: win.accent }
                        Hint { text: metricPanel.modelData.formula; Layout.fillWidth: true }
                        Hint { text: "Источник: " + metricPanel.modelData.source + " · " + metricPanel.modelData.id; Layout.fillWidth: true }
                    }
                }
            }
        }
    }
    Component {
        id: settingsView
        ColumnLayout {
            spacing: 20
            Hint { text: "НАСТРОЙТЕ FOCUS ПОД СЕБЯ"; color: win.accent; font.letterSpacing: 1 }
            Copy { text: "Настройки"; font.pixelSize: 32; font.bold: true }
            Panel {
                Layout.fillWidth: true; implicitHeight: 150
                ColumnLayout { anchors.fill: parent; anchors.margins: 22; spacing: 10
                    Copy { text: "Тема интерфейса"; font.pixelSize: 18; font.bold: true }
                    Hint { text: "Оформление сохраняется между запусками." }
                    RowLayout { Action { text: "☀ Светлая"; selected: !backend.dark; onClicked: backend.dark = false } Action { text: "◐ Тёмная"; selected: backend.dark; onClicked: backend.dark = true } }
                }
            }
            Panel {
                Layout.fillWidth: true; implicitHeight: aiColumn.implicitHeight + 44
                ColumnLayout { id: aiColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 } spacing: 12
                    Copy { text: "Подключение ИИ"; font.pixelSize: 18; font.bold: true }
                    Hint { text: "Провайдер: " + backend.provider + " · Модель: " + backend.model; Layout.fillWidth: true }
                    Hint { text: "Для ответов агентов нужна запущенная модель Ollama или ваш API-ключ. Задачи и документы доступны без ИИ."; Layout.fillWidth: true }
                    Action { text: "Настроить подключение"; primary: true; onClicked: aiDialog.open() }
                }
            }
            Panel {
                Layout.fillWidth: true; implicitHeight: otherColumn.implicitHeight + 44
                ColumnLayout { id: otherColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 } spacing: 12
                    Copy { text: "Файлы и голосовой ввод"; font.pixelSize: 18; font.bold: true }
                    Hint { text: "В «Документах» можно создавать папки, заметки и импортировать TXT, MD, CSV, JSON, DOCX или текстовый PDF. Импортируется один явно выбранный файл; сканы и архивы не читаются."; Layout.fillWidth: true }
                    Hint { text: "Для диктовки в поле запроса можно использовать системный ввод Windows: Win + H. Браузерное распознавание речи в Qt-версию не переносится."; Layout.fillWidth: true }
                }
            }
            Hint { text: "Focus — локальная демонстрация. Сообщения сохраняются в тестовый шлюз; реальная отправка писем не подключена."; Layout.fillWidth: true }
        }
    }
    Panel {
        id: chatPanel
        readonly property bool shown: win.loggedIn && win.chatOpen
        opacity: shown ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 100; bottom: parent.bottom; bottomMargin: 18 }
        width: win.page === "chat" ? win.width - 270 : Math.min(430, win.width - 300); z: 5
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 10
            RowLayout {
                Layout.preferredHeight: 92
                Image {
                    Layout.preferredWidth: 76; Layout.preferredHeight: 88
                    source: backend.assets + win.agentInfo(win.agent).image
                    fillMode: Image.PreserveAspectFit; verticalAlignment: Image.AlignBottom
                    asynchronous: true
                }
                ColumnLayout {
                    spacing: 3; Layout.fillWidth: true
                    Hint { text: "ВАШ АГЕНТ · " + win.agentInfo(win.agent).area.toUpperCase(); color: win.accent; font.pixelSize: 9; font.letterSpacing: 0.5 }
                    Copy { text: win.agentNames[win.agent]; font.pixelSize: 23; font.bold: true }
                    Hint { text: win.agentInfo(win.agent).description; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                Action { text: "×"; implicitWidth: 36; leftPadding: 0; rightPadding: 0; Accessible.name: "Закрыть чат"; onClicked: { win.chatOpen = false; intro.stop(); if (win.page === "chat") win.navigate("home") } }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 5
                Repeater { model: win.agents; delegate: Action { required property var modelData; text: modelData.name; selected: win.agent === modelData.key; Layout.fillWidth: true; implicitWidth: 70; leftPadding: 4; rightPadding: 4; onClicked: win.openAgent(modelData.key) } }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }
            ListView {
                id: chatList
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 9; model: conversation
                ScrollBar.vertical: ScrollBar {}
                header: Hint { width: chatList.width; text: "Здравствуйте! Выберите агента и напишите просьбу. Действия с данными выполняются после подтверждения.\n" }
                delegate: Rectangle {
                    id: messageBubble
                    required property string who
                    required property string body
                    width: chatList.width - 10; height: bubbleColumn.implicitHeight + 24
                    radius: 12; color: who === "Вы" ? win.soft : win.glassSoft
                    ColumnLayout {
                        id: bubbleColumn
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 } spacing: 5
                        Copy { text: messageBubble.who; color: win.accent; font.bold: true; font.pixelSize: 11 }
                        Copy { text: messageBubble.body; font.pixelSize: 13; Layout.fillWidth: true }
                    }
                }
            }
            Hint { text: "Думаю…"; visible: win.chatBusy; color: win.accent }
            Hint { text: "Прикреплён: " + win.homeAttachedFileName; visible: !!win.homeAttachedFileName; Layout.fillWidth: true; elide: Text.ElideRight }
            RowLayout {
                Action { text: "Файл"; implicitHeight: 32; onClicked: homeFileDialog.open() }
                Action { text: backend.recording ? "Стоп" : "Голос"; implicitHeight: 32; onClicked: { if (backend.recording) backend.stopMeetingRecording(); else { win.chatRecording = true; const path = backend.startMeetingRecording(); if (!String(path)) win.chatRecording = false } } }
                Action { text: "Распознать"; visible: !!win.chatAudioUrl; implicitHeight: 32; enabled: !win.chatBusy; onClicked: { win.chatBusy = true; win.api("/media/transcribe",{path:win.chatAudioUrl}).then(function(value) { prompt.text = value.text.slice(0,12000); win.chatBusy = false; win.chatAudioUrl = "" }).catch(function(e) { win.chatBusy = false; win.toast(e.message) }) } }
                Action { text: "Снять файл"; visible: !!win.homeAttachedFileName; implicitHeight: 32; onClicked: { win.homeAttachedFileName = ""; win.homeAttachedFileUrl = "" } }
            }
            RowLayout {
                Layout.fillWidth: true
                Field { id: prompt; Layout.fillWidth: true; placeholderText: "Спросите у " + win.agentNames[win.agent] + "…"; maximumLength: 12000; onAccepted: win.sendPrompt() }
                Action { text: "➤"; primary: true; implicitWidth: 44; enabled: !win.chatBusy && backend.ready; onClicked: win.sendPrompt() }
            }
            RowLayout {
                Action { text: "Проверить ИИ"; implicitHeight: 34; enabled: !win.chatBusy && backend.ready; onClicked: win.checkAi() }
                Action { text: "Подключение"; implicitHeight: 34; onClicked: aiDialog.open() }
            }
        }
    }
    Popup {
        id: featureSheet; objectName: "featureSheet"
        onClosed: { win.sheetRun++; win.sheetBusy = false }
        readonly property var f: win.features[win.sheetKey] || ({title:"", sub:"", glyph:"", placeholder:"", agent:"eva", prompt:"",tint:"#e4e0f2"})
        modal: true; focus: true; padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        anchors.centerIn: Overlay.overlay
        width: Math.min(700, win.width - 80); height: Math.min(660, win.height - 60)
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 120 } }
        Overlay.modal: Rectangle { color: "#66201e26" }
        background: Item {
            ShaderEffectSource { id: sheetCopy; visible: false; anchors.fill: parent; sourceItem: shell; sourceRect: Qt.rect(featureSheet.x, featureSheet.y, featureSheet.width, featureSheet.height) }
            Rectangle { id: sheetMask; anchors.fill: parent; radius: 38; visible: false; layer.enabled: true }
            MultiEffect { anchors.fill: parent; source: sheetCopy; blurEnabled: true; blur: 1.0; blurMax: 56; maskEnabled: true; maskSource: sheetMask }
            Rectangle {
                anchors.fill: parent; radius: 38; color: backend.dark ? "#d9262830" : Qt.tint("#cff4f3f6", featureSheet.f.tint); border.color: featureSheet.f.tint; border.width: 1.5
                Rectangle { height: 1.5; radius: 1; anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right; leftMargin: 34; rightMargin: 34 } color: "white" }
            }
        }
        contentItem: ColumnLayout {
            spacing: 12
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 24; Layout.leftMargin: 26; Layout.rightMargin: 26; spacing: 14
                Rectangle {
                    width: 52; height: 52; radius: 20; color: featureSheet.f.tint; border.color: "#e6ffffff"
                    Text { anchors.centerIn: parent; text: featureSheet.f.glyph; font.pixelSize: 22; color: win.ink }
                }
                ColumnLayout {
                    spacing: 2; Layout.fillWidth: true
                    Copy { text: featureSheet.f.title; font.pixelSize: 22; font.weight: Font.Bold; Layout.fillWidth: true }
                    Hint { text: String(featureSheet.f.mode || "инструмент").toUpperCase() + " · " + featureSheet.f.sub; Layout.fillWidth: true }
                }
                RoundBtn { size: 38; glyph: "✕"; onClicked: featureSheet.close() }
            }
            Hint { Layout.leftMargin: 26; Layout.rightMargin: 26; text: "Исполнитель: " + win.agentNames[featureSheet.f.agent] + " · " + win.agentInfo(featureSheet.f.agent).area; color: win.accent; font.weight: Font.DemiBold }
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: 26; Layout.rightMargin: 26; Layout.preferredHeight: 96
                visible: featureSheet.f.mode !== "calendar" && featureSheet.f.mode !== "files"
                radius: 24; color: win.glass; border.color: featureInput.activeFocus ? win.accent : win.fieldEdge; border.width: featureInput.activeFocus ? 2 : 1
                ScrollView {
                    anchors.fill: parent; anchors.margins: 6; clip: true
                    TextArea { id: featureInput; objectName: "featureInput"; placeholderText: featureSheet.f.placeholder; wrapMode: TextEdit.Wrap; selectByMouse: true; color: win.ink; placeholderTextColor: win.muted; background: null; onTextChanged: { if (length > 12000) remove(12000, length) } leftPadding: 12; rightPadding: 12 }
                }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: 26; Layout.rightMargin: 26; Layout.preferredHeight: 116
                visible: featureSheet.f.mode === "calendar"
                radius: 24; color: featureSheet.f.tint; border.color: win.glassEdge
                ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 7
                    Hint { text: "ПЕРИОД ПОИСКА · ЛОКАЛЬНОЕ ТЕСТОВОЕ РАСПИСАНИЕ"; color: win.ink; font.pixelSize: 10 }
                    RowLayout {
                        Layout.fillWidth: true
                        Field { id: calendarStartField; Layout.fillWidth: true; placeholderText: "Начало · ГГГГ-ММ-ДД ЧЧ:ММ" }
                        Field { id: calendarEndField; Layout.fillWidth: true; placeholderText: "Конец · ГГГГ-ММ-ДД ЧЧ:ММ" }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Hint { text: "Длительность встречи"; Layout.fillWidth: true }
                        ComboBox { id: calendarDuration; model: ["30","60","90","120"]; currentIndex: 1; Layout.preferredWidth: 120 }
                        Hint { text: "мин." }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: 26; Layout.rightMargin: 26; Layout.preferredHeight: 116
                visible: featureSheet.f.mode === "files"
                radius: 24; color: featureSheet.f.tint; border.color: win.glassEdge
                ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 8
                    Copy { text: "Личная библиотека"; font.pixelSize: 17; font.weight: Font.DemiBold }
                    Hint { text: "Добавьте один документ в Focus. Текст извлекается локально и сохраняется только в вашей базе."; Layout.fillWidth: true }
                    RowLayout {
                        Action { text: "Выбрать файл…"; primary: true; onClicked: documentFileDialog.open() }
                        Action { text: "Открыть библиотеку"; onClicked: { featureSheet.close(); win.navigate("documents") } }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 26; Layout.rightMargin: 26; spacing: 8
                Action { objectName: "featureRun"; text: win.sheetBusy ? (win.agentNames[featureSheet.f.agent] + " работает…") : (featureSheet.f.mode === "calendar" ? "Найти свободные окна" : "✦  Выполнить"); primary: true; enabled: !win.sheetBusy && backend.ready; onClicked: win.runFeature() }
                Action { visible: featureSheet.f.mode === "meeting" || featureSheet.f.mode === "agenda"; text: "＋ Создать встречу"; onClicked: { featureSheet.close(); win.newMeeting() } }
                Action {
                    visible: featureSheet.f.mode === "writer" && win.sheetOut.length > 0
                    text: "Сохранить в документы"
                    onClicked: {
                        const generated = win.sheetOut
                        featureSheet.close(); win.newDocument()
                        documentTitleField.text = "Черновик документа"
                        documentBodyField.text = generated
                    }
                }
                Action {
                    objectName: "featureOpen"; visible: !!featureSheet.f.open; text: featureSheet.f.open ? featureSheet.f.open.label : ""
                    onClicked: {
                        const o = featureSheet.f.open
                        featureSheet.close()
                        if (o.action === "task") win.newTask(featureInput.text.trim())
                        else if (o.search && featureInput.text.trim()) { win.navigate("documents"); win.searchDocuments(featureInput.text) }
                        else win.navigate(o.page)
                    }
                }
                Action {
                    visible: !!featureSheet.f.reply && win.sheetOut.length > 0; text: "Подготовить сообщение"
                    onClicked: { messageBody.text = win.sheetOut; messageError.text = ""; featureSheet.close(); messageDialog.open() }
                }
                Action { visible: win.sheetOut.length > 0; text: "Копировать"; onClicked: { featureOut.selectAll(); featureOut.copy(); featureOut.deselect(); win.toast("Скопировано") } }
                Item { Layout.fillWidth: true }
            }
            Copy { text: win.sheetErr; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true; Layout.leftMargin: 26; Layout.rightMargin: 26; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: 26; Layout.rightMargin: 26
                radius: 26; color: win.glassSoft; border.color: win.glassEdge
                ScrollView {
                    anchors.fill: parent; anchors.margins: 8; clip: true
                    TextArea {
                        id: featureOut; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
                        color: win.ink; background: null; leftPadding: 14; rightPadding: 14; topPadding: 10; font.pixelSize: 13
                        text: win.sheetOut || (win.sheetBusy ? "Собираю данные Focus и готовлю ответ…" : "Результат появится здесь. Действия с данными выполняются только после вашего подтверждения.")
                        opacity: win.sheetOut ? 1 : 0.6
                    }
                }
            }
            Item { Layout.preferredHeight: 18 }
        }
    }
    AnimatedDialog {
        id: pinPicker
        title: "Выберите функцию для закрепления"
        modal: true; anchors.centerIn: parent; width: 600; height: 520
        background: DialogBack {}
        contentItem: ColumnLayout {
            spacing: 12
            Hint { text: "Выберите инструмент для выбранного слота. Перетащить его можно и из левой панели."; Layout.fillWidth: true }
            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 8; Layout.fillWidth: true; Layout.fillHeight: true
                Repeater {
                    model: Object.keys(win.features)
                    delegate: Action {
                        required property string modelData
                        Layout.fillWidth: true; Layout.preferredHeight: 42
                        text: win.features[modelData].glyph + "  " + win.features[modelData].title
                        onClicked: { win.pinFeature(win.pinSlotToFill, modelData); pinPicker.close() }
                    }
                }
            }
            Action { text: "Закрыть"; Layout.alignment: Qt.AlignRight; onClicked: pinPicker.close() }
        }
    }
    FileDialog {
        id: homeFileDialog
        title: "Прикрепить документ к запросу"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Документы (*.txt *.md *.csv *.json *.docx *.pdf)", "Все файлы (*)"]
        onAccepted: win.attachHomeFile(selectedFile.toString())
    }
    FileDialog {
        id: documentFileDialog
        title: "Добавить документ в Focus"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Документы (*.txt *.md *.csv *.json *.docx *.pdf)", "Все файлы (*)"]
        onAccepted: win.importDocument(selectedFile.toString())
    }
    MediaPlayer { id: intro; audioOutput: AudioOutput { muted: true } }
    AnimatedDialog {
        id: taskDialog; background: DialogBack {} objectName: "taskDialog"; title: "Новая задача"; modal: true; anchors.centerIn: parent; width: 510
        closePolicy: Popup.NoAutoClose
        contentItem: ColumnLayout {
            spacing: 12
            Hint { text: "Проверьте название и срок. Перед сохранением появится подтверждение."; Layout.fillWidth: true }
            Copy { text: "Что нужно сделать?" }
            Field { id: taskTitle; objectName: "taskTitle"; Layout.fillWidth: true; maximumLength: 250; placeholderText: "Например, подготовить отчёт" }
            Copy { text: "Срок (необязательно)" }
            Field { id: taskDue; objectName: "taskDue"; Layout.fillWidth: true; placeholderText: "2026-12-01 18:00" }
            Hint { text: "Время — местное, как на вашем компьютере." }
            Copy { id: taskError; color: "#c14332"; Layout.fillWidth: true; visible: text.length > 0 }
            RowLayout {
                Action {
                    objectName: "reviewTask"; text: "Проверить задачу →"; primary: true; enabled: taskTitle.text.trim().length > 0 && !confirmDialog.working
                    onClicked: {
                        taskError.text = ""
                        let data = {status:"открыта"}
                        if (taskDue.text.trim()) {
                            const raw = taskDue.text.trim()
                            const parsed = Date.fromLocaleString(Qt.locale("en_US"), raw, "yyyy-MM-dd HH:mm")
                            if (isNaN(parsed.getTime())) { taskError.text = "Введите дату в формате ГГГГ-ММ-ДД ЧЧ:ММ."; return }
                            data.due = parsed.toISOString()
                        }
                        win.prepare("create_object", {kind:"task",title:taskTitle.text.trim(),data:data,visibility:"private"}, "Задача: " + taskTitle.text.trim() + "\nСрок: " + win.formatDate(data.due) + "\nВладелец: текущий пользователь")
                    }
                }
                Action { text: "Отмена"; enabled: !confirmDialog.working; onClicked: taskDialog.close() }
            }
        }
    }
    AnimatedDialog {
        id: folderDialog; background: DialogBack {} title: "Новая папка"; modal: true; anchors.centerIn: parent; width: 460
        contentItem: ColumnLayout {
            spacing: 12
            Hint { text: "Создайте личную папку для документов. Она будет видна только в вашей библиотеке."; Layout.fillWidth: true }
            Field { id: folderNameField; objectName: "folderNameField"; Layout.fillWidth: true; maximumLength: 80; placeholderText: "Например, Проекты" }
            Copy { id: folderError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            RowLayout {
                Action { objectName: "saveFolderAction"; text: win.folderBusy ? "Сохраняю…" : "Создать папку"; primary: true; enabled: !win.folderBusy && folderNameField.text.trim().length > 0; onClicked: win.saveFolder() }
                Action { text: "Отмена"; enabled: !win.folderBusy; onClicked: folderDialog.close() }
            }
        }
    }
    AnimatedDialog {
        id: documentDialog; background: DialogBack {} title: "Новый документ"; modal: true; anchors.centerIn: parent; width: 610; height: 570
        contentItem: ColumnLayout {
            spacing: 10
            Hint { text: "Заметка сохраняется в выбранную папку вашей локальной базы Focus."; Layout.fillWidth: true }
            Field { id: documentTitleField; objectName: "documentTitleField"; Layout.fillWidth: true; maximumLength: 250; placeholderText: "Название документа" }
            ComboBox { id: documentFolderBox; Layout.fillWidth: true; model: ["Без папки"].concat(win.folders.map(function(f) { return f.name })) }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                TextArea {
                    id: documentBodyField
                    objectName: "documentBodyField"
                    placeholderText: "Текст документа…"; wrapMode: TextEdit.Wrap; selectByMouse: true; color: win.ink
                    background: Rectangle { color: win.bg; radius: 12; border.color: win.line }
                }
            }
            Copy { id: documentError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            RowLayout {
                Action { objectName: "saveDocumentAction"; text: win.documentBusy ? "Сохраняю…" : "Сохранить документ"; primary: true; enabled: !win.documentBusy && documentTitleField.text.trim().length > 0 && documentBodyField.text.trim().length > 0; onClicked: win.saveDocument() }
                Action { text: "Отмена"; enabled: !win.documentBusy; onClicked: documentDialog.close() }
            }
        }
    }
    AnimatedDialog {
        id: meetingDialog; background: DialogBack {} title: "Новая встреча"; modal: true; anchors.centerIn: parent; width: 570; height: 600
        contentItem: ColumnLayout {
            spacing: 10
            Hint { text: "Добавление через экран проверки. Используется тестовый календарь Focus."; Layout.fillWidth: true }
            Field { id: meetingTitleField; objectName: "meetingTitleField"; Layout.fillWidth: true; maximumLength: 250; placeholderText: "Название встречи" }
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout { Layout.fillWidth: true; Copy { text: "Начало" } Field { id: meetingStartField; objectName: "meetingStartField"; Layout.fillWidth: true; placeholderText: "ГГГГ-ММ-ДД ЧЧ:ММ" } }
                ColumnLayout { Layout.fillWidth: true; Copy { text: "Окончание" } Field { id: meetingEndField; objectName: "meetingEndField"; Layout.fillWidth: true; placeholderText: "ГГГГ-ММ-ДД ЧЧ:ММ" } }
            }
            Copy { text: "Повестка (необязательно)" }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                TextArea { id: meetingAgendaField; objectName: "meetingAgendaField"; wrapMode: TextEdit.Wrap; selectByMouse: true; color: win.ink; placeholderText: "Цель, вопросы и материалы"; background: Rectangle { color: win.bg; radius: 12; border.color: win.line } }
            }
            Copy { id: meetingError; color: "#c14332"; visible: text.length > 0; Layout.fillWidth: true }
            RowLayout {
                Action { objectName: "reviewMeetingAction"; text: "Проверить и сохранить →"; primary: true; enabled: meetingTitleField.text.trim().length > 0 && !confirmDialog.working; onClicked: win.reviewMeeting() }
                Action { text: "Отмена"; enabled: !confirmDialog.working; onClicked: meetingDialog.close() }
            }
        }
    }
    AnimatedDialog {
        id: messageDialog; background: DialogBack {} title: "Подготовить сообщение"; modal: true; anchors.centerIn: parent; width: 540
        closePolicy: Popup.NoAutoClose
        property bool improving: false
        contentItem: ColumnLayout {
            spacing: 11
            Hint { text: "Тестовый шлюз: реальной отправки в почту или мессенджеры нет."; Layout.fillWidth: true }
            Field { id: recipient; placeholderText: "Кому"; Layout.fillWidth: true; maximumLength: 5000 }
            Field { id: messageTitle; text: "Сообщение от Focus"; placeholderText: "Тема"; Layout.fillWidth: true; maximumLength: 5000 }
            ScrollView { Layout.fillWidth: true; Layout.preferredHeight: 150; TextArea { id: messageBody; placeholderText: "Текст сообщения"; wrapMode: TextEdit.Wrap; selectByMouse: true; color: win.ink; background: Rectangle { color: win.bg; radius: 10; border.color: win.line } } }
            Action {
                text: messageDialog.improving ? "Eva готовит текст…" : "✦ Улучшить текст с Eva"
                enabled: !messageDialog.improving && messageBody.text.trim().length > 0
                onClicked: {
                    messageDialog.improving = true
                    win.api("/focus/chat", {agent:"eva",text:"Переформулируй как вежливое сообщение. Не добавляй факты. Верни только текст: " + messageBody.text}).then(function(data) { messageBody.text = data.answer; messageDialog.improving = false }).catch(function(error) { messageError.text = error.message; messageDialog.improving = false })
                }
            }
            Copy { id: messageError; color: "#c14332"; Layout.fillWidth: true; visible: text.length > 0 }
            RowLayout {
                Action {
                    text: "Просмотреть →"; primary: true; enabled: recipient.text.trim().length > 0 && messageTitle.text.trim().length > 0 && messageBody.text.trim().length > 0 && !confirmDialog.working && !messageDialog.improving
                    onClicked: win.prepare("send_message", {recipient:recipient.text.trim(),title:messageTitle.text.trim(),body:messageBody.text.trim()}, "Кому: " + recipient.text + "\nТема: " + messageTitle.text + "\n\n" + messageBody.text + "\n\nБудет сохранено в тестовый шлюз.")
                }
                Action { text: "Отмена"; enabled: !confirmDialog.working && !messageDialog.improving; onClicked: messageDialog.close() }
            }
        }
    }
    AnimatedDialog {
        id: confirmDialog; background: DialogBack {} objectName: "confirmDialog"; title: "Проверьте действие"; modal: true; anchors.centerIn: parent; width: 540
        closePolicy: Popup.NoAutoClose
        property int proposalId: 0
        property string kind: ""
        property string refreshPage: "tasks"
        property string preview: ""
        property string errorText: ""
        property bool working: false
        contentItem: ColumnLayout {
            spacing: 16
            Hint { text: "Данные ещё не изменены. Проверьте действие перед подтверждением."; Layout.fillWidth: true }
            ScrollView { id: previewScroll; Layout.fillWidth: true; Layout.preferredHeight: 210; contentWidth: availableWidth; Copy { text: confirmDialog.preview; width: previewScroll.availableWidth } }
            Copy { text: confirmDialog.errorText; visible: text.length > 0; color: "#c14332"; Layout.fillWidth: true }
            RowLayout {
                Action {
                    objectName: "confirmAction"; text: confirmDialog.working ? "Сохраняем…" : "Подтвердить"; primary: true; enabled: !confirmDialog.working
                    onClicked: {
                        confirmDialog.working = true
                        win.api("/proposals/" + confirmDialog.proposalId + "/confirm", {}).then(function() {
                            confirmDialog.working = false; confirmDialog.close()
                            win.toast(confirmDialog.kind === "send_message" ? "Записано в тестовый шлюз. Реальное письмо не отправлено." : "Действие подтверждено и сохранено.")
                            if (confirmDialog.kind === "create_object" || confirmDialog.kind === "update_object")
                                win.navigate(confirmDialog.refreshPage || "tasks")
                        }).catch(function(error) { confirmDialog.working = false; confirmDialog.errorText = error.message })
                    }
                }
                Action {
                    text: "Отменить"; enabled: !confirmDialog.working
                    onClicked: {
                        confirmDialog.working = true
                        win.api("/proposals/" + confirmDialog.proposalId + "/cancel", {}).then(function() { confirmDialog.working = false; confirmDialog.close() }).catch(function(error) { confirmDialog.working = false; confirmDialog.errorText = error.message })
                    }
                }
            }
        }
    }
    AnimatedDialog {
        id: detailDialog; background: DialogBack {} modal: true; anchors.centerIn: parent; width: 660; height: 500; standardButtons: Dialog.Close
        contentItem: ScrollView { contentWidth: availableWidth; TextArea { id: detailText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; color: win.ink } }
    }
    AnimatedDialog {
        id: aiDialog; background: DialogBack {} title: "Подключение ИИ"; modal: true; anchors.centerIn: parent; width: 550
        onOpened: { providerBox.currentIndex = ["ollama","openai","anthropic","gemini"].indexOf(backend.provider); modelField.text = backend.model; apiKey.text = ""; externalConsent.checked = false }
        onClosed: apiKey.text = ""
        contentItem: ColumnLayout {
            spacing: 12
            Copy { text: "Провайдер" }
            ComboBox { id: providerBox; model: ["Ollama (на компьютере)","OpenAI","Anthropic","Google Gemini"]; Layout.fillWidth: true; onActivated: modelField.text = currentIndex === 0 ? "llama3.1" : currentIndex === 1 ? "gpt-4.1-mini" : "" }
            Copy { text: "Название модели" }
            Field { id: modelField; Layout.fillWidth: true; placeholderText: "Идентификатор модели из вашего API-аккаунта" }
            Hint { text: "Ollama должна быть запущена, а выбранная модель — загружена."; visible: providerBox.currentIndex === 0; Layout.fillWidth: true }
            Field { id: apiKey; visible: providerBox.currentIndex !== 0; Layout.fillWidth: true; placeholderText: "Ваш API-ключ"; echoMode: TextInput.Password }
            Hint { visible: backend.keySaved; text: "Ключ сохранён под защитой Windows. Его значение не показывается."; Layout.fillWidth: true }
            CheckBox { id: rememberKey; text: "Запомнить новый ключ на этом компьютере"; visible: providerBox.currentIndex !== 0; checked: false }
            CheckBox { id: externalConsent; visible: providerBox.currentIndex !== 0; Layout.fillWidth: true; text: "Разрешаю передачу запросов и тестовых данных\nвыбранному сервису (возможна оплата API)."; font.pixelSize: 12 }
            Hint { text: "Ключ используется только до закрытия программы. После применения нужно войти в Focus снова; сохранённые задачи останутся."; Layout.fillWidth: true }
            RowLayout {
                Action {
                    text: "Применить"; primary: true
                    enabled: modelField.text.trim().length > 0 && (providerBox.currentIndex === 0 || ((apiKey.text.trim().length > 0 || backend.keySaved) && externalConsent.checked))
                    onClicked: { backend.configure(["ollama","openai","anthropic","gemini"][providerBox.currentIndex], modelField.text, apiKey.text, externalConsent.checked, rememberKey.checked); apiKey.text = ""; aiDialog.close() }
                }
                Action { text: "Отмена"; onClicked: aiDialog.close() }
            }
        }
    }
    Rectangle {
        visible: win.notice.length > 0; z: 20
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
        width: Math.min(620, win.width - 60); height: toastText.implicitHeight + 28; color: win.ink; radius: 12
        Text { id: toastText; anchors.fill: parent; anchors.margins: 14; text: win.notice; textFormat: Text.PlainText; color: win.surface; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
    }
    Item {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 32; z: 50
        MouseArea {
            anchors.fill: parent; anchors.rightMargin: 144
            onPressed: win.startSystemMove()
            onDoubleClicked: win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized()
        }
        Row {
            x: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            Rectangle { width: 11; height: 11; radius: 6; color: "#4795ee"; anchors.verticalCenter: parent.verticalCenter; Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: "white" } }
            Text { text: win.title; font.pixelSize: 11; font.weight: Font.DemiBold; color: win.ink }
        }
        Row {
            anchors { right: parent.right; top: parent.top } height: parent.height
            Repeater {
                model: ["−", "□", "×"]
                delegate: Rectangle {
                    required property string modelData; required property int index
                    width: 48; height: 32; color: captionMouse.containsMouse ? (index === 2 ? "#e76777" : "#50ffffff") : "transparent"
                    Text { anchors.centerIn: parent; text: modelData; font.pixelSize: index === 2 ? 24 : 20; color: win.ink }
                    MouseArea { id: captionMouse; anchors.fill: parent; hoverEnabled: true; onClicked: index === 0 ? win.showMinimized() : index === 1 ? (win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized()) : win.close() }
                    Accessible.role: Accessible.Button; Accessible.name: ["Свернуть","Развернуть","Закрыть"][index]
                }
            }
        }
    }
    AnimatedDialog {
        id: utilityDialog
        objectName: "utilityDialog"
        anchors.centerIn: parent; width: Math.min(720, win.width - 100); height: Math.min(560, win.height - 100)
        modal: true; title: win.utilityTitle; standardButtons: Dialog.Close
        background: DialogBack {}
        ScrollView {
            anchors.fill: parent; contentWidth: availableWidth; clip: true
            ColumnLayout {
                width: parent.width; spacing: 12
                Copy { text: win.utilityError; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Repeater {
                    model: win.utilityRecords
                    delegate: Panel {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: utilityColumn.implicitHeight + 28
                        ColumnLayout {
                            id: utilityColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            Copy { text: modelData.title; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            Hint { text: modelData.detail; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        }
                    }
                }
            }
        }
    }

    component ResizeEdge: MouseArea {
        property int edges: 0
        visible: win.visibility !== Window.Maximized
        z: 100
        onPressed: win.startSystemResize(edges)
    }
    ResizeEdge { x: 0; y: 6; width: 6; height: win.height - 12; edges: Qt.LeftEdge; cursorShape: Qt.SizeHorCursor }
    ResizeEdge { x: win.width - 6; y: 6; width: 6; height: win.height - 12; edges: Qt.RightEdge; cursorShape: Qt.SizeHorCursor }
    ResizeEdge { x: 6; y: 0; width: win.width - 12; height: 6; edges: Qt.TopEdge; cursorShape: Qt.SizeVerCursor }
    ResizeEdge { x: 6; y: win.height - 6; width: win.width - 12; height: 6; edges: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor }
    ResizeEdge { x: 0; y: 0; width: 8; height: 8; edges: Qt.TopEdge | Qt.LeftEdge; cursorShape: Qt.SizeFDiagCursor }
    ResizeEdge { x: win.width - 8; y: 0; width: 8; height: 8; edges: Qt.TopEdge | Qt.RightEdge; cursorShape: Qt.SizeBDiagCursor }
    ResizeEdge { x: 0; y: win.height - 8; width: 8; height: 8; edges: Qt.BottomEdge | Qt.LeftEdge; cursorShape: Qt.SizeBDiagCursor }
    ResizeEdge { x: win.width - 8; y: win.height - 8; width: 8; height: 8; edges: Qt.BottomEdge | Qt.RightEdge; cursorShape: Qt.SizeFDiagCursor }

}
