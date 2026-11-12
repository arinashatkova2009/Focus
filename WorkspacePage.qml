import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: page
    objectName: "workspacePage"
    property string section: "tasks"
    property var api
    property int revision: 0
    property bool dark: false
    property bool recording: false
    property bool savedKey: false
    property var snapshot: ({})
    property string query: ""
    property string filter: "Все"
    property string error: ""
    property string aiAnswer: ""
    property bool busy: false
    property bool aiBusy: false
    property int requestNumber: 0
    property bool initialized: false
    property var selected: null
    property string taskView: "Доска"
    property string selectedFile: ""
    property bool liveDemo: false
    property int liveStep: 0
    readonly property color ink: dark ? "#f3eefb" : "#2c2940"
    readonly property color muted: dark ? "#c6bbd8" : "#81788f"
    readonly property color accent: "#8272b0"
    readonly property var titles: ({tasks:"Контроль поручений",meetings:"Совещания",mail:"Анализ почты",calendar:"Календарь",documents:"Документы",knowledge:"База знаний",users:"Пользователи",analytics:"Аналитика",settings:"Настройки",audit:"Журнал аудита",chat:"ИИ-ассистент"})
    readonly property var subtitles: ({tasks:"Приоритеты, сроки и ответственность — в одном пространстве",meetings:"Записи, расшифровки, решения и поручения",mail:"Разбор входящих и ответы, которые остаётся проверить",calendar:"Ваш день, свободные интервалы и время для важных задач",documents:"Документы, решения и прозрачный маршрут согласования",knowledge:"Корпоративные знания с проверяемыми источниками",users:"Сотрудники, роли и доступ к рабочим данным",analytics:"Показатели команды и понятные выводы",settings:"Ваше пространство, предпочтения и подключения",audit:"Действия, предупреждения и проверка целостности",chat:"Eva, Leo, Nick и Robby — ваша команда помощников"})
    implicitHeight: content.implicitHeight
    signal createTask(string title)
    signal createMeeting()
    signal createDocument()
    signal importDocument()
    signal taskStatusRequested(var record, string status)
    signal documentDecision(var record, string status)
    signal openDocument(int ident)
    signal composeMessage(string recipient, string title, string body)
    signal exportRequested(string format, string title, var rows)
    signal connectionRequested()
    signal themeRequested(bool value)
    signal recordRequested(bool start)
    signal chatRequested(string text)

    function refresh() {
        if (typeof api !== "function") return
        const run = ++requestNumber
        busy = true; error = ""
        api("/workspace/" + section).then(function(value) {
            if (run !== requestNumber) return
            snapshot = value; busy = false
            if (section === "mail" && !selected) selected = (snapshot.mail || [])[0] || null
            if (section === "meetings") transcript.text = snapshot.transcript || ""
            if (section === "settings") { profileName.text = (snapshot.profile || {}).display_name || snapshot.user || ""; profilePosition.text = (snapshot.profile || {}).position || "" }
        }).catch(function(e) { if (run === requestNumber) { error = e.message; busy = false } })
    }
    function act(body) { error = ""; api("/workspace/action", body).then(function() { refresh() }).catch(function(e) { error = e.message }) }
    function ask(question, context) {
        if (aiBusy) return
        aiBusy = true; error = ""; aiAnswer = ""
        api("/workspace/ai", {question:question,context:String(context || "").slice(0,24000)}).then(function(value) { aiAnswer = value.answer; aiBusy = false }).catch(function(e) { error = e.message; aiBusy = false })
    }
    function tasks(status) { return (snapshot.tasks || []).filter(function(x) { return (!status || x.status === status) && (filter === "Все" || x.priority === filter) && (x.title + " " + x.owner).toLowerCase().indexOf(query.toLowerCase()) >= 0 }) }
    function documents() { return (snapshot.documents || []).filter(function(x) { return (x.title + " " + x.text).toLowerCase().indexOf(query.toLowerCase()) >= 0 }) }
    function mails() { return (snapshot.mail || []).filter(function(x) { return (filter === "Все" || x.tag === filter || x.status === filter) && (x.subject + x.from + x.body).toLowerCase().indexOf(query.toLowerCase()) >= 0 }) }
    function events() { return (snapshot.events || []).filter(function(x) { return (filter === "Все" || x.severity === filter) && (x.action + x.detail).toLowerCase().indexOf(query.toLowerCase()) >= 0 }) }
    function reportRows() {
        let rows = [{title:"Задачи",detail:String((snapshot.metrics || {}).tasks || 0)},{title:"Завершено",detail:String((snapshot.metrics || {}).completed || 0)},{title:"Документы",detail:String((snapshot.metrics || {}).documents || 0)},{title:"Встречи",detail:String((snapshot.metrics || {}).meetings || 0)}]
        return rows.concat(tasks("").map(function(x) { return {title:x.title,detail:x.owner + " · " + x.status + " · " + String(x.due || "").slice(0,10)} }))
    }
    function scheduleLabel(hour) { return (snapshot.schedule || []).filter(function(x) { return x.hour === hour }).map(function(x) { return x.title }).join("; ") }
    function variant(index) {
        if (!selected) return
        const texts = ["Спасибо, материалы получил. Изучу и вернусь с ответом.","Добрый день! Благодарю за информацию по теме «" + selected.subject + "». Проверю материалы и сообщу решение после согласования.","Спасибо за письмо. Уточните, пожалуйста, желаемый срок ответа и какие вопросы требуют решения в первую очередь."]
        draft.text = texts[index]
    }
    function receivedRecording(path) { selectedFile = String(path); error = "Запись готова. Нажмите «Расшифровать», чтобы передать её OpenAI." }
    onSectionChanged: { query = ""; filter = "Все"; selected = null; aiAnswer = ""; if (initialized) { refresh(); reveal.restart() } }
    onRevisionChanged: if (initialized) refresh()
    onSnapshotChanged: if (initialized) trendCanvas.requestPaint()
    Component.onCompleted: { initialized = true; refresh(); reveal.restart() }
    NumberAnimation { id: reveal; target: content; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }

    component Copy: Label { color: page.ink; textFormat: Text.PlainText; wrapMode: Text.WordWrap }
    component Small: Copy { font.pixelSize: 12; color: page.muted }
    component Heading: Copy { font.pixelSize: 20; font.weight: Font.DemiBold }
    component Glass: Rectangle {
        radius: 24; border.width: 1; border.color: page.dark ? "#35ffffff" : "#e6ffffff"
        gradient: Gradient { GradientStop { position: 0; color: page.dark ? "#b3323041" : "#ceffffff" } GradientStop { position: 1; color: page.dark ? "#a6292736" : "#70ffffff" } }
        Rectangle { height: 1; color: "white"; opacity: 0.65; anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 22; rightMargin: 22; topMargin: 1 } }
    }
    component Pill: Button {
        id: button
        property bool primary: false
        property bool chosen: false
        implicitHeight: 38; leftPadding: 16; rightPadding: 16
        scale: down ? 0.97 : hovered ? 1.02 : 1
        Behavior on scale { NumberAnimation { duration: 140 } }
        contentItem: Text { text: button.text; font.pixelSize: 12; font.weight: Font.DemiBold; color: button.primary ? "white" : page.ink; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        background: Rectangle { radius: height / 2; border.color: button.chosen ? page.accent : "#eaffffff"; border.width: button.chosen ? 1.8 : 1; gradient: Gradient { GradientStop { position: 0; color: button.primary ? "#a194c7" : "#f7ffffff" } GradientStop { position: 0.48; color: button.primary ? "#746393" : "#82ffffff" } GradientStop { position: 1; color: button.primary ? "#8c7dad" : "#d9e4e4f5" } } }
    }
    component Input: TextField { color: page.ink; implicitHeight: 40; leftPadding: 16; rightPadding: 16; selectByMouse: true; background: Rectangle { radius: 20; color: page.dark ? "#302c3b" : "#85ffffff"; border.color: parent.activeFocus ? page.accent : "#ccffffff" } }
    component Badge: Rectangle {
        property string text: ""
        property color tint: "#81709e"
        implicitWidth: badgeText.implicitWidth + 22; implicitHeight: 25; radius: 13; color: Qt.rgba(tint.r,tint.g,tint.b,0.12)
        Text { id: badgeText; anchors.centerIn: parent; text: parent.text; color: parent.tint; font.pixelSize: 10; font.weight: Font.DemiBold }
    }
    component Stat: Glass {
        property string label: ""
        property string value: ""
        property string note: ""
        implicitHeight: 104
        Column { anchors { left: parent.left; top: parent.top; margins: 16 } spacing: 5; Small { text: parent.parent.label } Copy { text: parent.parent.value; font.pixelSize: 28; font.weight: Font.DemiBold } Small { text: parent.parent.note; font.pixelSize: 10 } }
    }

    ColumnLayout {
        id: content
        width: parent.width; spacing: 18
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 5; Small { text: "FOCUS  /  " + (page.titles[page.section] || "") ; font.letterSpacing: 1 } Copy { text: page.titles[page.section] || ""; font.pixelSize: 30; font.weight: Font.DemiBold } Small { text: page.subtitles[page.section] || ""; Layout.fillWidth: true } }
            Badge { text: "Рабочие данные + демо" }
        }
        Glass {
            Layout.fillWidth: true; implicitHeight: errorText.implicitHeight + 22; visible: page.error.length > 0
            Copy { id: errorText; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11 } text: page.error; color: "#a35f69"; font.pixelSize: 12 }
        }
        BusyIndicator { running: page.busy; visible: running; Layout.alignment: Qt.AlignHCenter }

        // TASKS — actual records retain the server's confirmation flow; demo cards are private.
        ColumnLayout {
            visible: page.section === "tasks"; Layout.fillWidth: true; spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Input { Layout.fillWidth: true; placeholderText: "Найти поручение или сотрудника…"; onTextChanged: page.query = text }
                ComboBox { model: ["Все","Высокий","Обычный"]; onActivated: page.filter = currentText }
                Pill { text: "Доска"; chosen: page.taskView === text; onClicked: page.taskView = text }
                Pill { objectName: "ganttView"; text: "Гант"; chosen: page.taskView === text; onClicked: page.taskView = text }
                Pill { text: "+ Поручение"; primary: true; onClicked: page.createTask("") }
            }
            RowLayout {
                visible: page.taskView === "Доска"; Layout.fillWidth: true; spacing: 12
                Repeater {
                    model: [{status:"open",title:"Новые",color:"#8e89af"},{status:"in_progress",title:"В работе",color:"#6f9bad"},{status:"review",title:"На проверке",color:"#bd9b6e"},{status:"done",title:"Готово",color:"#80a394"}]
                    delegate: Glass {
                        id: lane
                        required property var modelData
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; implicitHeight: laneColumn.implicitHeight + 28
                        border.color: laneDrop.containsDrag ? page.accent : "#b3ffffff"
                        ColumnLayout {
                            id: laneColumn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 } spacing: 12
                            RowLayout { Layout.fillWidth: true; Copy { text: lane.modelData.title; font.weight: Font.DemiBold; Layout.fillWidth: true } Badge { text: String(page.tasks(lane.modelData.status).length); tint: lane.modelData.color } }
                            Repeater {
                                model: page.tasks(lane.modelData.status)
                                delegate: Item {
                                    id: taskCard
                                    required property var modelData
                                    property var record: modelData
                                    Layout.fillWidth: true; implicitHeight: 150; z: taskDrag.active ? 20 : 0
                                    Glass {
                                        id: dragVisual; width: parent.width; height: parent.height
                                        Drag.active: taskDrag.active; Drag.keys: ["focus-task"]; Drag.source: taskCard; Drag.hotSpot.x: width / 2; Drag.hotSpot.y: 30
                                        ColumnLayout {
                                            anchors.fill: parent; anchors.margins: 12; spacing: 7
                                            Copy { text: taskCard.record.title; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; maximumLineCount: 3; elide: Text.ElideRight }
                                            Small { text: taskCard.record.owner; Layout.fillWidth: true }
                                            Small { text: String(taskCard.record.due || "Без срока").slice(0,10); Layout.fillWidth: true }
                                            RowLayout { Layout.fillWidth: true; Badge { text: taskCard.record.demo ? "Демо" : "Рабочая" } Item { Layout.fillWidth: true } Pill { text: "→"; implicitHeight: 26; leftPadding: 9; rightPadding: 9; onClicked: page.taskStatusRequested(taskCard.record,({open:"in_progress",in_progress:"review",review:"done",done:"open"})[taskCard.record.status]) } }
                                        }
                                        DragHandler { id: taskDrag; target: dragVisual; onActiveChanged: if (!active) { dragVisual.Drag.drop(); dragVisual.x = 0; dragVisual.y = 0 } }
                                    }
                                }
                            }
                            Small { visible: page.tasks(lane.modelData.status).length === 0; text: "Перетащите поручение сюда"; Layout.fillWidth: true }
                        }
                        DropArea { id: laneDrop; anchors.fill: parent; keys: ["focus-task"]; onDropped: function(drop) { if (drop.source && drop.source.record) page.taskStatusRequested(drop.source.record,lane.modelData.status) } }
                    }
                }
            }
            Glass {
                visible: page.taskView === "Гант"; Layout.fillWidth: true; implicitHeight: ganttRows.implicitHeight + 36
                ColumnLayout {
                    id: ganttRows; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 16
                    Small { text: "Демо длительности · сроки указаны в карточках поручений" }
                    Repeater { model: page.tasks(""); delegate: RowLayout { required property var modelData; required property int index; Layout.fillWidth: true; Copy { text: modelData.title; Layout.preferredWidth: 260; font.pixelSize: 12 } Rectangle { Layout.fillWidth: true; implicitHeight: 28; radius: 14; color: "#42ffffff"; Rectangle { x: 8 + (index % 4) * parent.width * 0.10; width: parent.width * (0.30 + (index % 3) * 0.10); height: parent.height; radius: 14; color: modelData.status === "done" ? "#96b5a9" : "#b0a2d0" } } } }
                }
            }
            Pill { text: page.aiBusy ? "Готовлю сводку…" : "ИИ: сводка просроченных задач"; enabled: !page.aiBusy; onClicked: page.ask("Сделай краткую сводку просроченных и рискованных поручений. Укажи фактические сроки, не выдумывай действия.",JSON.stringify(page.snapshot.tasks)) }
        }

        ColumnLayout {
            visible: page.section === "meetings"; Layout.fillWidth: true; spacing: 14
            RowLayout { Layout.fillWidth: true; Pill { text: "+ Совещание"; primary: true; onClicked: page.createMeeting() } Pill { text: "Загрузить аудио / видео"; onClicked: audioDialog.open() } Pill { text: page.recording ? "■ Остановить запись" : "● Записать микрофон"; onClicked: page.recordRequested(!page.recording) } Pill { text: "Демо live"; chosen: page.liveDemo; onClicked: { page.liveDemo = !page.liveDemo; page.liveStep = 0; if (page.liveDemo) transcript.text = "" } } }
            Small { text: page.selectedFile ? "Выбрана запись: " + decodeURIComponent(page.selectedFile.split('/').pop()) : "Запись микрофона и расшифровка файла — реальные функции. Демо live показывает сценарий потоковой расшифровки."; Layout.fillWidth: true }
            Glass {
                Layout.fillWidth: true; implicitHeight: 270
                TextArea { id: transcript; anchors.fill: parent; anchors.margins: 16; color: page.ink; textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap; selectByMouse: true; placeholderText: "Текст расшифровки или протокола…"; background: null }
            }
            RowLayout {
                Pill { text: "Расшифровать в OpenAI"; enabled: page.selectedFile.length > 0 && !page.aiBusy; onClicked: { page.aiBusy = true; page.error = ""; page.api("/media/transcribe",{path:page.selectedFile}).then(function(x) { transcript.text = x.text; page.aiBusy = false }).catch(function(e) { page.error = e.message; page.aiBusy = false }) } }
                Pill { text: "Сохранить расшифровку"; onClicked: page.act({action:"transcript",text:transcript.text}) }
                Pill { text: "ИИ: резюме и поручения"; primary: true; enabled: !page.aiBusy; onClicked: page.ask("Подготовь резюме совещания: решения, открытые вопросы, поручения, ответственные и сроки. Отметь недостающие сведения; не утверждай, что что-либо сохранено.",transcript.text) }
                Pill { text: "+ Поручение"; onClicked: page.createTask("") }
            }
            Repeater { model: page.snapshot.meetings || []; delegate: Glass { required property var modelData; Layout.fillWidth: true; implicitHeight: 76; Column { anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 } spacing: 6; Copy { text: modelData.title; font.weight: Font.DemiBold } Small { text: String(modelData.start).replace('T',' ').slice(0,16) + " · " + modelData.agenda; width: parent.width } } } }
        }

        ColumnLayout {
            visible: page.section === "mail"; Layout.fillWidth: true
            RowLayout { Layout.fillWidth: true; Input { Layout.fillWidth: true; placeholderText: "Поиск по письмам…"; onTextChanged: page.query = text } ComboBox { model: ["Все","Непрочитано","Важно","Проекты","Встречи","Документы"]; onActivated: page.filter = currentText } }
            Small { text: "Демонстрационная почта · письма вымышлены · отправка доступна в тестовый шлюз после подтверждения"; Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true; spacing: 14
                Glass {
                    Layout.preferredWidth: Math.max(230,page.width * 0.31); Layout.alignment: Qt.AlignTop; implicitHeight: mailList.implicitHeight + 28
                    ColumnLayout { id: mailList; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 } spacing: 8
                        Repeater { model: page.mails(); delegate: Rectangle { required property var modelData; Layout.fillWidth: true; implicitHeight: 100; radius: 18; color: page.selected && page.selected.id === modelData.id ? "#dbffffff" : "#38ffffff"; Column { anchors { fill: parent; margins: 12 } spacing: 5; Copy { text: modelData.from; font.weight: Font.DemiBold; font.pixelSize: 12 } Copy { text: modelData.subject; width: parent.width; font.pixelSize: 12; maximumLineCount: 2; elide: Text.ElideRight } Small { text: modelData.tag + " · " + modelData.time } } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { page.selected = modelData; page.act({action:"read_mail",id:modelData.id}) } } } }
                    }
                }
                Glass {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; implicitHeight: mailDetail.implicitHeight + 36
                    ColumnLayout { id: mailDetail; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 14
                        Heading { text: page.selected ? page.selected.subject : "Выберите письмо"; Layout.fillWidth: true }
                        Small { text: page.selected ? page.selected.from + " · " + page.selected.address : ""; Layout.fillWidth: true }
                        Copy { text: page.selected ? page.selected.body : "Входящие находятся слева"; Layout.fillWidth: true; font.pixelSize: 14 }
                        Flow { Layout.fillWidth: true; spacing: 8; Repeater { model: ["Важно","Проект","На ответ"]; delegate: Badge { required property string modelData; text: modelData } } }
                        RowLayout { Pill { text: "Саммари"; enabled: !page.aiBusy && !!page.selected; onClicked: page.ask("Кратко резюмируй письмо: суть, срок, необходимое решение.",page.selected.body) } Pill { text: "ИИ: 3 ответа"; enabled: !page.aiBusy && !!page.selected; onClicked: page.ask("Предложи три варианта ответа на письмо: краткий, деловой, с уточняющими вопросами. Не выдумывай одобрение или отправку.",page.selected.body) } }
                        Small { text: "Примеры черновиков (демо)" }
                        RowLayout { Pill { text: "Кратко"; onClicked: page.variant(0) } Pill { text: "Деловой"; onClicked: page.variant(1) } Pill { text: "Уточнить"; onClicked: page.variant(2) } }
                        TextArea { id: draft; Layout.fillWidth: true; implicitHeight: 125; color: page.ink; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; placeholderText: "Черновик ответа — проверьте перед подтверждением…"; background: Rectangle { radius: 18; color: "#65ffffff" } }
                        Pill { text: "Проверить и отправить →"; primary: true; enabled: !!page.selected && draft.text.trim().length > 0; onClicked: page.composeMessage(page.selected.address,"Re: " + page.selected.subject,draft.text) }
                    }
                }
            }
            Small { text: "Исходящих в личном тестовом шлюзе: " + (page.snapshot.outbox || []).length }
        }

        ColumnLayout {
            visible: page.section === "calendar"; Layout.fillWidth: true; spacing: 14
            RowLayout { Heading { text: "План дня"; Layout.fillWidth: true } Pill { text: "ИИ: распределить задачи"; enabled: !page.aiBusy; onClicked: page.ask("Предложи распределение задач на день с 9 до 18 с обедом в 13:00. Учитывай уже занятые часы. Это предложение, не сохранение календаря.",JSON.stringify({tasks:page.snapshot.tasks,schedule:page.snapshot.schedule,meetings:page.snapshot.meetings})) } Pill { text: "+ Встреча"; primary: true; onClicked: page.createMeeting() } }
            RowLayout { Layout.fillWidth: true; ComboBox { id: scheduleTask; Layout.fillWidth: true; model: page.tasks("").map(function(x) { return x.title }) } ComboBox { id: scheduleHour; model: ["09:00","10:00","11:00","12:00","14:00","15:00","16:00","17:00"] } Pill { text: "Запланировать"; onClicked: page.act({action:"schedule",title:scheduleTask.currentText,hour:Number(scheduleHour.currentText.slice(0,2))}) } }
            Small { text: "Перетащите поручение на свободный час" }
            Flow {
                Layout.fillWidth: true; spacing: 8
                Repeater { model: page.tasks("").filter(function(x) { return x.status !== "done" }); delegate: Glass {
                    id: calendarChip
                    required property var modelData
                    property var record: modelData
                    width: 220; height: 46; z: dragChip.active ? 20 : 1
                    Drag.active: dragChip.active; Drag.keys: ["focus-task"]; Drag.source: calendarChip
                    Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
                    Copy { anchors.fill: parent; anchors.margins: 12; text: calendarChip.modelData.title; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; font.pixelSize: 12 }
                    DragHandler { id: dragChip; onActiveChanged: if (!active) { calendarChip.Drag.drop(); calendarChip.x = 0; calendarChip.y = 0; calendarChip.parent.forceLayout() } }
                } }
            }
            Repeater { model: 11; delegate: Glass { required property int index; readonly property int hour: 9 + index; Layout.fillWidth: true; implicitHeight: 64; RowLayout { anchors.fill: parent; anchors.margins: 12; Copy { text: String(parent.parent.hour).padStart(2,'0') + ":00"; Layout.preferredWidth: 70; font.weight: Font.DemiBold } Copy { text: page.scheduleLabel(parent.parent.hour) || (parent.parent.hour === 13 ? "Обед / перерыв" : "Свободный интервал"); Layout.fillWidth: true; color: page.scheduleLabel(parent.parent.hour) ? page.ink : page.muted } Badge { text: page.scheduleLabel(parent.parent.hour) ? "Запланировано" : "Свободно"; tint: "#73948b" } } DropArea { anchors.fill: parent; keys: ["focus-task"]; onDropped: function(drop) { if (drop.source && drop.source.record) page.act({action:"schedule",title:drop.source.record.title,hour:parent.hour}) } } } }
        }

        ColumnLayout {
            visible: page.section === "documents" || page.section === "knowledge"; Layout.fillWidth: true; spacing: 14
            RowLayout { Layout.fillWidth: true; Input { Layout.fillWidth: true; placeholderText: page.section === "knowledge" ? "Большой поиск по корпоративной базе…" : "Название, содержание или автор…"; onTextChanged: page.query = text } Pill { text: "+ Документ"; onClicked: page.createDocument() } Pill { text: "Загрузить"; primary: true; onClicked: page.importDocument() } }
            RowLayout {
                Layout.fillWidth: true; spacing: 14
                Glass {
                    visible: page.section === "knowledge"; Layout.preferredWidth: 175; Layout.alignment: Qt.AlignTop; implicitHeight: 250
                    ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 10; Heading { text: "Библиотека"; font.pixelSize: 16 } Pill { text: "Все документы"; onClicked: page.query = "" } Pill { text: "Договоры"; onClicked: page.query = "договор" } Pill { text: "Регламенты"; onClicked: page.query = "регламент" } Small { text: "Недавно просмотрено: " + (page.snapshot.recent || []).length } Item { Layout.fillHeight: true } }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    Repeater { model: page.documents(); delegate: Glass { required property var modelData; Layout.fillWidth: true; implicitHeight: documentRow.implicitHeight + 30
                        ColumnLayout { id: documentRow; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 15 } spacing: 10
                            RowLayout { Layout.fillWidth: true; Copy { text: modelData.title; font.weight: Font.DemiBold; Layout.fillWidth: true } Badge { text: modelData.status } }
                            Small { text: modelData.author + " · версия " + modelData.version + " · источник №" + modelData.id; Layout.fillWidth: true }
                            RowLayout { Pill { text: "Просмотр"; onClicked: { page.selected = modelData; page.act({action:"recent",id:modelData.id}); documentDialog.open() } } Pill { text: "Утвердить"; visible: page.section === "documents"; enabled: page.snapshot.role === "director" || page.snapshot.role === "manager"; onClicked: page.documentDecision(modelData,"Утверждён") } Pill { text: "Отклонить"; visible: page.section === "documents"; enabled: page.snapshot.role === "director" || page.snapshot.role === "manager"; onClicked: page.documentDecision(modelData,"Отклонён") } Pill { text: "ИИ: риски"; enabled: !page.aiBusy; onClicked: page.ask("Выдели риски документа: сроки, обязательства, противоречия. Укажи, что требуется проверить человеку. Источник №" + modelData.id,modelData.text) } }
                            Small { visible: page.section === "documents"; text: "Маршрут: автор → руководитель → решение · изменение сохраняется после подтверждения" }
                        }
                    } }
                    Glass { visible: !page.documents().length; Layout.fillWidth: true; implicitHeight: 110; Column { anchors { fill: parent; margins: 18 } spacing: 8; Heading { text: "Начните с первого материала" } Small { text: "Добавьте регламент, договор или рабочую заметку — источник останется в вашей области доступа."; width: parent.width } } }
                }
            }
            Glass {
                visible: page.section === "knowledge"; Layout.fillWidth: true; implicitHeight: 112
                RowLayout { anchors.fill: parent; anchors.margins: 18; Input { id: knowledgeQuestion; Layout.fillWidth: true; placeholderText: "Спросить по найденным источникам…" } Pill { text: "Спросить Robby"; primary: true; enabled: !page.aiBusy && knowledgeQuestion.text.length > 0; onClicked: page.ask("Ответь на вопрос по данным источникам. Для каждого факта укажи [№ источника]. Если сведений нет — скажи об этом. Вопрос: " + knowledgeQuestion.text,JSON.stringify(page.documents().slice(0,8).map(function(x) { return {source_id:x.id,title:x.title,text:x.text.slice(0,2500)} }))) } }
            }
        }

        ColumnLayout {
            visible: page.section === "users"; Layout.fillWidth: true; spacing: 14
            RowLayout { Layout.fillWidth: true; Stat { Layout.fillWidth: true; label: "Доступные сотрудники"; value: String((page.snapshot.people || []).length); note: "Область определяется ролью" } Stat { Layout.fillWidth: true; label: "Лицензии / демо-план"; value: (page.snapshot.people || []).length + " / 32"; note: "Иллюстрация распределения мест" } Stat { Layout.fillWidth: true; label: "Ваша роль"; value: ({admin:"Админ",director:"Директор",manager:"Руководитель",employee:"Сотрудник"})[page.snapshot.role] || ""; note: "Изменение ролей — только администратору" } }
            Input { Layout.fillWidth: true; placeholderText: "Сотрудник или подразделение…"; onTextChanged: page.query = text }
            ProgressBar { Layout.fillWidth: true; from: 0; to: 32; value: Math.min(32,(page.snapshot.people || []).length); Accessible.name: "Занято мест в демонстрационном плане" }
            Pill { text: "ИИ: проверить подозрительную активность"; enabled: !page.aiBusy && page.snapshot.role !== "admin"; onClicked: page.ask("Проверь доступные события на подозрительную активность. Укажи основания, а не предположения о людях. Не делай автоматических блокировок.",JSON.stringify({people:page.snapshot.people,events:page.snapshot.events})) }
            Repeater { model: (page.snapshot.people || []).filter(function(x) { return (x.name + x.department).toLowerCase().indexOf(page.query.toLowerCase()) >= 0 }); delegate: Glass { required property var modelData; Layout.fillWidth: true; implicitHeight: 86; RowLayout { anchors.fill: parent; anchors.margins: 16; Rectangle { width: 42; height: 42; radius: 21; color: "#dcd3ec"; Text { anchors.centerIn: parent; text: modelData.name.slice(0,1); color: page.ink; font.pixelSize: 20 } } ColumnLayout { Layout.fillWidth: true; Copy { text: modelData.name; font.weight: Font.DemiBold } Small { text: modelData.department + " · " + (modelData.active ? "Активен" : "Заблокирован") } } Badge { text: modelData.role } ComboBox { enabled: page.snapshot.role === "admin" && modelData.id !== page.snapshot.user_id; model: ["employee","manager","director","admin"]; currentIndex: ["employee","manager","director","admin"].indexOf(modelData.role); onActivated: { page.selected = {id:modelData.id,name:modelData.name,newRole:currentText}; roleDialog.open() } } } } }
        }

        ColumnLayout {
            visible: page.section === "analytics"; Layout.fillWidth: true; spacing: 14
            RowLayout { Layout.fillWidth: true; ComboBox { id: period; model: ["Неделя","Месяц","Квартал"]; onActivated: trendCanvas.requestPaint() } Item { Layout.fillWidth: true } Pill { text: "PDF"; onClicked: page.exportRequested("pdf","Аналитика Focus · " + period.currentText,page.reportRows()) } Pill { text: "Excel"; onClicked: page.exportRequested("xlsx","Аналитика Focus · " + period.currentText,page.reportRows()) } }
            RowLayout { Layout.fillWidth: true; Stat { Layout.fillWidth: true; label: "Поручений"; value: String((page.snapshot.metrics || {}).tasks || 0); note: "Включая демонстрационную доску" } Stat { Layout.fillWidth: true; label: "Завершено"; value: String((page.snapshot.metrics || {}).completed || 0); note: "Текущий статус" } Stat { Layout.fillWidth: true; label: "Документов"; value: String((page.snapshot.metrics || {}).documents || 0); note: "Только доступные источники" } }
            Glass { Layout.fillWidth: true; implicitHeight: 260; ColumnLayout { anchors.fill: parent; anchors.margins: 20; Heading { text: "Динамика выполнения" } Small { text: "Демонстрационный исторический ряд · выбран период «" + period.currentText + "»" } Canvas { id: trendCanvas; Layout.fillWidth: true; Layout.fillHeight: true; onWidthChanged: requestPaint(); onPaint: { const ctx = getContext("2d"); ctx.reset(); const list = page.snapshot.trend || []; if (!list.length) return; const count = period.currentIndex === 0 ? 7 : period.currentIndex === 1 ? 10 : 12; const values = list.slice(-count); ctx.strokeStyle = "#ece6f4"; ctx.lineWidth = 1; for (let j=1;j<4;j++) { ctx.beginPath(); ctx.moveTo(0,height*j/4); ctx.lineTo(width,height*j/4); ctx.stroke() } const step = width/values.length; for (let i=0;i<values.length;i++) { const bar = values[i]/100*(height-20); ctx.fillStyle = i === values.length-1 ? "#8b79b1" : "#c7b9e1"; ctx.fillRect(i*step+8,height-bar,Math.max(4,step-16),bar) } } } } }
            Pill { text: page.aiBusy ? "Анализирую…" : "ИИ: выводы по статистике"; enabled: !page.aiBusy; primary: true; onClicked: page.ask("Дай краткие выводы по показателям: факты, риски, рекомендации. Исторический ряд демонстрационный, не представляй его реальным.",JSON.stringify({metrics:page.snapshot.metrics,trend:page.snapshot.trend,period:period.currentText})) }
        }

        ColumnLayout {
            visible: page.section === "settings"; Layout.fillWidth: true; spacing: 14
            Glass { Layout.fillWidth: true; implicitHeight: profileBox.implicitHeight + 36; ColumnLayout { id: profileBox; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 12; Heading { text: "Профиль" } Input { id: profileName; Layout.fillWidth: true; placeholderText: "Как к вам обращаться" } Input { id: profilePosition; Layout.fillWidth: true; placeholderText: "Должность" } Pill { text: "Сохранить профиль"; onClicked: page.api("/me/profile",{display_name:profileName.text,position:profilePosition.text}).then(function() { page.refresh() }).catch(function(e) { page.error = e.message }) } } }
            Glass { Layout.fillWidth: true; implicitHeight: 192; ColumnLayout { anchors.fill: parent; anchors.margins: 18; Heading { text: "Уведомления и персонализация" } RowLayout { Switch { text: "Уведомления"; checked: !!(page.snapshot.preferences || {}).notifications; onClicked: page.act({action:"preferences",values:{notifications:checked}}) } Switch { text: "Звук"; checked: !!(page.snapshot.preferences || {}).sound; onClicked: page.act({action:"preferences",values:{sound:checked}}) } ComboBox { model: ["Русский","English"]; currentIndex: (page.snapshot.preferences || {}).language === "English" ? 1 : 0; onActivated: page.act({action:"preferences",values:{language:currentText}}) } } Small { text: "Выбранный язык применяется к ответам ИИ. Роли и права проверяются сервером." } RowLayout { Pill { text: "Светлая"; chosen: !page.dark; onClicked: page.themeRequested(false) } Pill { text: "Тёмная"; chosen: page.dark; onClicked: page.themeRequested(true) } } } }
            Glass { Layout.fillWidth: true; implicitHeight: 180; ColumnLayout { anchors.fill: parent; anchors.margins: 18; Heading { text: "Интеграции" } Small { text: page.savedKey ? "OpenAI: ключ сохранён под защитой текущего пользователя Windows" : "OpenAI: введите свой ключ в защищённом окне подключения"; Layout.fillWidth: true } Small { text: "Корпоративная почта: тестовый шлюз · календарь: локальное планирование"; Layout.fillWidth: true } RowLayout { Pill { text: "Подключение ИИ"; primary: true; onClicked: page.connectionRequested() } Pill { text: "Проверить реальный ответ"; enabled: !page.aiBusy; onClicked: page.ask("Коротко поприветствуй пользователя как рабочий помощник Focus.","") } } } }
        }

        ColumnLayout {
            visible: page.section === "audit"; Layout.fillWidth: true; spacing: 14
            RowLayout { Layout.fillWidth: true; Input { Layout.fillWidth: true; placeholderText: "Поиск действия или события…"; onTextChanged: page.query = text } ComboBox { model: ["Все","INFO","WARNING","CRITICAL"]; onActivated: page.filter = currentText } Pill { text: "ИИ: отчёт по событиям"; enabled: !page.aiBusy; onClicked: page.ask("Разбери журнал: подозрительные события, причины, что проверить. Не называй отсутствие ошибок гарантией безопасности.",JSON.stringify(page.events().slice(0,40))) } }
            Small { text: page.snapshot.role === "admin" ? "Доступны события компании" : "Показаны только действия текущего пользователя" }
            Repeater { model: page.events(); delegate: Glass { required property var modelData; Layout.fillWidth: true; implicitHeight: 84; RowLayout { anchors.fill: parent; anchors.margins: 15; Badge { text: modelData.severity; tint: modelData.severity === "CRITICAL" ? "#ad6474" : modelData.severity === "WARNING" ? "#ac9065" : "#819e99" } ColumnLayout { Layout.fillWidth: true; Copy { text: modelData.action; font.weight: Font.DemiBold } Small { text: String(modelData.at).replace('T',' ').slice(0,19) + " · " + (modelData.detail || modelData.result); Layout.fillWidth: true } } } } }
            Glass { visible: !page.events().length; Layout.fillWidth: true; implicitHeight: 95; Copy { anchors.fill: parent; anchors.margins: 20; text: "По выбранному фильтру событий нет. Измените фильтр или выполните действие в приложении." } }
        }

        Glass {
            visible: page.aiAnswer.length > 0 || page.aiBusy; Layout.fillWidth: true; implicitHeight: answerBox.implicitHeight + 36
            ColumnLayout { id: answerBox; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 12; Heading { text: page.aiBusy ? "Помощник думает…" : "Черновик ИИ" } Copy { text: page.aiAnswer; Layout.fillWidth: true; font.pixelSize: 14 } Small { text: "Проверьте ответ по источникам. Действия не выполняются автоматически."; Layout.fillWidth: true } Flow { visible: page.section === "knowledge"; Layout.fillWidth: true; spacing: 6; Repeater { model: page.documents().slice(0,8); delegate: Pill { required property var modelData; text: "Источник №" + modelData.id; onClicked: page.openDocument(modelData.id) } } } }
        }
        Small { text: "Личное пространство · изменения сохраняются для вашего аккаунта"; Layout.topMargin: 5 }
    }

    Timer { interval: 1400; repeat: true; running: page.liveDemo; onTriggered: { const lines = ["Анна: Согласуем бюджет до пятницы.","Михаил: Интеграция готова на 85%.","Елена: Проверю риски договора.","Решение: демонстрация завтра в 11:00."]; if (page.liveStep >= lines.length) { page.liveDemo = false; return } transcript.text += (transcript.text ? "\n" : "") + lines[page.liveStep++]; } }
    FileDialog { id: audioDialog; title: "Выберите запись — передача начнётся только по кнопке расшифровки"; nameFilters: ["Записи (*.mp3 *.mp4 *.m4a *.wav *.ogg *.webm *.flac)"]; onAccepted: page.selectedFile = String(selectedFile) }
    Dialog {
        id: documentDialog; anchors.centerIn: parent; width: Math.min(720,page.width); height: 500; modal: true; title: page.selected && page.selected.title ? page.selected.title : "Документ"; standardButtons: Dialog.Close
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 } }
        background: Glass {}
        ScrollView { anchors.fill: parent; TextArea { text: page.selected ? page.selected.text + "\n\nИстория согласования\n" + ((((page.selected.raw || {}).data || {}).approval_history || []).map(function(x) { return String(x.at).slice(0,19).replace('T',' ') + " · " + x.by + " · " + x.status }).join("\n") || "Решений пока нет. Текущая версия: " + page.selected.version) : ""; readOnly: true; textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap; color: page.ink; background: null } }
    }
    Dialog {
        id: roleDialog; anchors.centerIn: parent; width: 450; modal: true; title: "Подтвердить изменение роли"; standardButtons: Dialog.Ok | Dialog.Cancel
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 } }
        background: Glass {}
        Copy { width: parent.width; text: page.selected ? page.selected.name + " → " + page.selected.newRole + "\nТекущие сессии сотрудника будут завершены." : "" }
        onAccepted: page.api("/admin/users/" + page.selected.id + "/role",{role:page.selected.newRole}).then(function() { page.refresh() }).catch(function(e) { page.error = e.message })
    }
}
