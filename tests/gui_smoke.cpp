#include "FocusBackend.h"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTemporaryDir>
#include <QDir>
#include <QJSValue>
#include <QSignalSpy>
#include <QSettings>
#include <QtTest>
#include <functional>

class GuiSmoke : public QObject {
    Q_OBJECT
    QQmlApplicationEngine engine;
    QObject *root = nullptr;
    FocusBackend *backend = nullptr;
    QVariantList records() {
        const auto value = root->property("records");
        return value.metaType() == QMetaType::fromType<QJSValue>()
            ? value.value<QJSValue>().toVariant().toList() : value.toList();
    }
    QVariantList folders() {
        const auto value = root->property("folders");
        return value.metaType() == QMetaType::fromType<QJSValue>()
            ? value.value<QJSValue>().toVariant().toList() : value.toList();
    }
    bool hasRecord(const QString &title) {
        for (const auto &entry : records())
            if (entry.toMap().value("title").toString() == title) return true;
        return false;
    }
    void screenshot(const QString &name) {
        QTest::qWait(250);
        auto *window = qobject_cast<QQuickWindow *>(root);
        QVERIFY(window);
        QVERIFY(window->grabWindow().save(QString::fromUtf8(FOCUS_SOURCE_DIR) + "/test-output/" + name + ".png"));
    }
    void click(const char *name) {
        auto *item = root->findChild<QQuickItem *>(name);
        if (!item) {
            // Repeater delegates can have a different QObject owner from their visual parent.
            std::function<QQuickItem *(QQuickItem *)> findVisual = [&](QQuickItem *parent) -> QQuickItem * {
                if (parent->objectName() == QLatin1String(name)) return parent;
                for (auto *child : parent->childItems())
                    if (auto *found = findVisual(child)) return found;
                return nullptr;
            };
            item = findVisual(qobject_cast<QQuickWindow *>(root)->contentItem());
        }
        QVERIFY2(item, name);
        QTest::mouseClick(item->window(), Qt::LeftButton, Qt::NoModifier,
                          item->mapToScene(QPointF(item->width()/2, item->height()/2)).toPoint());
    }
private slots:
    void initTestCase() {
        engine.loadFromModule("focus", "Main");
        QVERIFY(!engine.rootObjects().isEmpty());
        root = engine.rootObjects().first();
        // Test windows ignore physical desktop clicks; QTest events still go directly to Qt.
        qobject_cast<QQuickWindow *>(root)->setFlag(Qt::WindowTransparentForInput, true);
        backend = root->findChild<FocusBackend *>();
        QVERIFY(backend);
        QTRY_VERIFY_WITH_TIMEOUT(backend->ready(), 30000);
        QCOMPARE(root->property("authMode").toString(), QString("welcome"));
        screenshot("00-welcome");
    }
    void nativeUiAndPersistence() {
        // Welcome screen -> "Войти". This is a synthetic demo account in a disposable database.
        click("chooseLogin");
        QTRY_COMPARE_WITH_TIMEOUT(root->property("authMode").toString(), QString("login"), 5000);
        QTest::qWait(700); // the form fades in; wait until it is fully shown
        screenshot("01-login");
        auto *username = root->findChild<QObject *>("username");
        auto *password = root->findChild<QObject *>("password");
        QVERIFY(username);
        QVERIFY(password);
        username->setProperty("text", "arina");
        password->setProperty("text", "incorrect-demo-password");
        click("loginButton");
        QTRY_VERIFY_WITH_TIMEOUT(!root->property("loginError").toString().isEmpty(), 10000);
        QVERIFY(!root->property("loggedIn").toBool());
        screenshot("01-login-error");
        password->setProperty("text", "1234");
        click("loginButton");
        QTRY_VERIFY_WITH_TIMEOUT(root->property("loggedIn").toBool(), 10000);
        screenshot("02-home");
        QVERIFY(QMetaObject::invokeMethod(root, "pinFeature", Q_ARG(QVariant, 0), Q_ARG(QVariant, "planner")));
        QCOMPARE(backend->loadPinnedFeatures().at(0).toString(), QString("planner"));
        QVERIFY(QMetaObject::invokeMethod(root, "unpinFeature", Q_ARG(QVariant, 0)));
        QCOMPARE(backend->loadPinnedFeatures().at(0).toString(), QString(""));
        auto *sheet = root->findChild<QObject *>("featureSheet");
        QVERIFY(sheet);
        const QStringList features = {"control", "summary", "replies", "docs", "planner", "inbox", "meetings", "calendar", "agenda", "approvals", "reports", "time", "search", "delegate", "voice", "files", "coach"};
        for (const auto &key : features) {
            QVERIFY(QMetaObject::invokeMethod(root, "openFeature", Q_ARG(QVariant, key)));
            QTRY_VERIFY(sheet->property("visible").toBool());
            QCOMPARE(root->property("sheetKey").toString(), key);
            QVERIFY(QMetaObject::invokeMethod(sheet, "close"));
            QTRY_VERIFY(!sheet->property("visible").toBool());
        }
        QVERIFY(QMetaObject::invokeMethod(root, "openFeature", Q_ARG(QVariant, "replies")));
        QTRY_VERIFY(sheet->property("visible").toBool());
        QTest::qWait(200);
        click("featureRun");
        QTRY_VERIFY(!root->property("sheetErr").toString().isEmpty());
        screenshot("02-feature-validation");
        QVERIFY(QMetaObject::invokeMethod(sheet, "close"));
        QTRY_VERIFY(!sheet->property("visible").toBool());
        QVERIFY(QMetaObject::invokeMethod(root, "openFeature", Q_ARG(QVariant, "control")));
        QTRY_VERIFY(sheet->property("visible").toBool());
        QTest::qWait(200);
        screenshot("02-feature-control");
        click("featureOpen");
        QTRY_COMPARE(root->property("page").toString(), QString("tasks"));
        QTRY_VERIFY(!root->property("loading").toBool());
        QVERIFY2(root->property("pageError").toString().isEmpty(), qPrintable(root->property("pageError").toString()));
        const int before = records().size();
        QVERIFY(before > 0);
        QVERIFY(QMetaObject::invokeMethod(root, "newTask", Q_ARG(QVariant, QString::fromUtf8("Проверка Qt — тестовая задача"))));
        auto *due = root->findChild<QObject *>("taskDue");
        QVERIFY(due);
        due->setProperty("text", "2030-12-01 18:00");
        QTest::qWait(200);
        click("reviewTask");
        auto *confirm = root->findChild<QObject *>("confirmDialog");
        QVERIFY(confirm);
        QTRY_VERIFY_WITH_TIMEOUT(confirm->property("visible").toBool(), 10000);
        QVERIFY(confirm->property("preview").toString().contains("01.12.2030 18:00"));
        screenshot("03-confirm");
        click("confirmAction");
        QTRY_VERIFY_WITH_TIMEOUT(!confirm->property("visible").toBool(), 10000);
        QTRY_COMPARE(records().size(), before + 1);
        screenshot("04-tasks");
        QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, "documents")));
        QTRY_VERIFY(!root->property("loading").toBool());
        QVERIFY(records().size() > 0);
        QVERIFY(QMetaObject::invokeMethod(root, "newFolder"));
        auto *folderName = root->findChild<QObject *>("folderNameField");
        QVERIFY(folderName);
        folderName->setProperty("text", "GUI smoke folder");
        click("saveFolderAction");
        QTRY_VERIFY_WITH_TIMEOUT(!folders().isEmpty(), 10000);
        QVERIFY(QMetaObject::invokeMethod(root, "newDocument"));
        auto *documentTitle = root->findChild<QObject *>("documentTitleField");
        auto *documentBody = root->findChild<QObject *>("documentBodyField");
        QVERIFY(documentTitle && documentBody);
        documentTitle->setProperty("text", "GUI smoke note");
        documentBody->setProperty("text", "A local note in a personal folder.");
        click("saveDocumentAction");
        QTRY_VERIFY_WITH_TIMEOUT(hasRecord("GUI smoke note"), 10000);
        screenshot("05-documents");
        QVERIFY(QMetaObject::invokeMethod(root, "searchDocuments", Q_ARG(QVariant, QString::fromUtf8("Альфа"))));
        QTRY_VERIFY(!root->property("loading").toBool());
        QVERIFY(records().size() > 0);
        QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, "meetings")));
        QTRY_VERIFY(!root->property("loading").toBool());
        QVERIFY(records().size() > 0);
        QVERIFY(QMetaObject::invokeMethod(root, "newMeeting"));
        auto *meetingTitle = root->findChild<QObject *>("meetingTitleField");
        auto *meetingStart = root->findChild<QObject *>("meetingStartField");
        auto *meetingEnd = root->findChild<QObject *>("meetingEndField");
        QVERIFY(meetingTitle && meetingStart && meetingEnd);
        meetingTitle->setProperty("text", "GUI smoke meeting");
        meetingStart->setProperty("text", "2030-12-02 10:00");
        meetingEnd->setProperty("text", "2030-12-02 11:00");
        click("reviewMeetingAction");
        QTRY_VERIFY_WITH_TIMEOUT(root->findChild<QObject *>("confirmDialog")->property("visible").toBool(), 10000);
        click("confirmAction");
        QTRY_VERIFY_WITH_TIMEOUT(!root->findChild<QObject *>("confirmDialog")->property("visible").toBool(), 10000);
        QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, "meetings")));
        QTRY_VERIFY_WITH_TIMEOUT(hasRecord("GUI smoke meeting"), 10000);
        screenshot("06-meetings");
        QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, "analytics")));
        QTRY_VERIFY(!root->property("loading").toBool());
        screenshot("07-overview");
        QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, "settings")));
        screenshot("08-settings");
        QVERIFY(QMetaObject::invokeMethod(root, "openUtility", Q_ARG(QVariant, "employees")));
        QTest::qWait(700);
        QVERIFY(root->property("utilityError").toString().isEmpty());
        auto *utility = root->findChild<QObject *>("utilityDialog");
        QVERIFY(utility);
        QVERIFY(QMetaObject::invokeMethod(utility, "close"));
        QVERIFY(QMetaObject::invokeMethod(root, "openUtility", Q_ARG(QVariant, "security")));
        QTest::qWait(700);
        QVERIFY(root->property("utilityError").toString().isEmpty());
        screenshot("08-security");
        QVERIFY(QMetaObject::invokeMethod(utility, "close"));
        backend->setDark(true);
        screenshot("09-dark");
        backend->setDark(false);
        QVERIFY(QMetaObject::invokeMethod(root, "openAgent", Q_ARG(QVariant, "eva")));
        screenshot("10-assistant");
        // A restart must close the old transport and retain the saved task.
        backend->restart();
        QVERIFY(!root->property("loggedIn").toBool());
        QTRY_VERIFY_WITH_TIMEOUT(backend->ready(), 30000);
        QCOMPARE(root->property("authMode").toString(), QString("welcome"));
        username->setProperty("text", "arina");
        password->setProperty("text", "1234");
        QVERIFY(QMetaObject::invokeMethod(root, "login"));
        QTRY_VERIFY(root->property("loggedIn").toBool());
        QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, "tasks")));
        QTRY_VERIFY(!root->property("loading").toBool());
        QCOMPARE(records().size(), before + 1);
    }
    void interactiveSections() {
        QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, "home")));
        QTest::qWait(400);
        auto *welcome = root->findChild<QQuickItem *>("homeWelcomeWord");
        QVERIFY(welcome);
        const QRectF before(welcome->mapToScene(QPointF()), QSizeF(welcome->width(),welcome->height()));
        QVERIFY(QMetaObject::invokeMethod(root, "openAgent", Q_ARG(QVariant, "eva")));
        QTest::qWait(400);
        QCOMPARE(QRectF(welcome->mapToScene(QPointF()), QSizeF(welcome->width(),welcome->height())), before);
        QVERIFY(before.left() >= 230);
        screenshot("11-stable-home-and-agent");
        const QStringList sections = {"tasks","meetings","mail","calendar","documents","knowledge","users","analytics","settings","audit"};
        for (const auto &section : sections) {
            QVERIFY(QMetaObject::invokeMethod(root, "navigate", Q_ARG(QVariant, section)));
            QTest::qWait(350);
            auto *workspace = root->findChild<QObject *>("workspacePage");
            QVERIFY2(workspace, qPrintable(section));
            QTRY_VERIFY_WITH_TIMEOUT(!workspace->property("busy").toBool(), 10000);
            QVERIFY2(workspace->property("error").toString().isEmpty(), qPrintable(workspace->property("error").toString()));
            screenshot("12-page-" + section);
            if (section == "tasks") {
                workspace->setProperty("taskView", QString::fromUtf8("Гант"));
                screenshot("12-gantt");
            }
        }
        const auto pdf = QString::fromUtf8(FOCUS_SOURCE_DIR) + "/test-output/analytics-export.pdf";
        QVERIFY(backend->exportPdf(QUrl::fromLocalFile(pdf), "Focus export", QVariantList{QVariantMap{{"title","Test metric"},{"detail","42"}}}));
        QFile file(pdf); QVERIFY(file.open(QIODevice::ReadOnly)); QVERIFY(file.read(5) == "%PDF-");
    }
    void registrationFlow() {
        QVERIFY(QMetaObject::invokeMethod(root, "logout"));
        QTRY_VERIFY(!root->property("loggedIn").toBool());
        QTRY_COMPARE(root->property("authMode").toString(), QString("welcome"));
        click("chooseRegister");
        QTRY_COMPARE_WITH_TIMEOUT(root->property("authMode").toString(), QString("register"), 5000);
        QTest::qWait(700);
        screenshot("01-register");
        auto field = [&](const char *name) {
            auto *item = root->findChild<QObject *>(name);
            if (!item) qWarning("missing field %s", name);
            return item;
        };
        QVERIFY(field("regName") && field("regUser") && field("regPass") && field("regPass2"));
        field("regName")->setProperty("text", "Test User");
        field("regUser")->setProperty("text", "tester.qt");
        field("regPass")->setProperty("text", "Strong-pass-2026");
        // mismatching confirmation is rejected on the client, nothing is sent
        field("regPass2")->setProperty("text", "Strong-pass-0000");
        click("registerButton");
        QTRY_VERIFY(!root->property("loginError").toString().isEmpty());
        QVERIFY(!root->property("loggedIn").toBool());
        screenshot("01-register-error");
        field("regPass2")->setProperty("text", "Strong-pass-2026");
        click("registerButton");
        QTRY_VERIFY_WITH_TIMEOUT(root->property("loggedIn").toBool(), 10000);
        QCOMPARE(root->property("userName").toString(), QString("Test User"));
        // sign out and sign in again with the new account (login is case-insensitive)
        QVERIFY(QMetaObject::invokeMethod(root, "logout"));
        QTRY_VERIFY(!root->property("loggedIn").toBool());
        QVERIFY(QMetaObject::invokeMethod(root, "showAuth", Q_ARG(QVariant, "login")));
        QTest::qWait(700);
        root->findChild<QObject *>("username")->setProperty("text", "Tester.QT");
        root->findChild<QObject *>("password")->setProperty("text", "Strong-pass-2026");
        click("loginButton");
        QTRY_VERIFY_WITH_TIMEOUT(root->property("loggedIn").toBool(), 10000);
    }
};

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QDir().mkpath(QString::fromUtf8(FOCUS_SOURCE_DIR) + "/test-output");
    QTemporaryDir temp(QString::fromUtf8(FOCUS_SOURCE_DIR) + "/test-output/gui-XXXXXX");
    if (!temp.isValid()) return 2;
    qputenv("FOCUS_DATA_DIR", temp.path().toUtf8());
    QCoreApplication::setOrganizationName("FocusTests");
    QCoreApplication::setApplicationName("GuiSmoke");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, temp.path());
    QQuickStyle::setStyle("Basic");
    GuiSmoke test;
    return QTest::qExec(&test, argc, argv);
}
#include "gui_smoke.moc"
