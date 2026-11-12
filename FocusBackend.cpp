#include "FocusBackend.h"
#include <QAudioDevice>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJSValue>
#include <QNetworkReply>
#include <QNetworkProxy>
#include <QSettings>
#include <QStandardPaths>
#include <QStringList>
#include <QUuid>
#include <QFile>
#include <QSaveFile>
#include <QPdfWriter>
#include <QPageSize>
#include <QPainter>
#include <QFontMetrics>
#include <QMediaDevices>
#include <QMediaFormat>

FocusBackend::FocusBackend(QObject *parent) : QObject(parent)
{
    m_root = QCoreApplication::applicationDirPath();
    if (!QFileInfo::exists(m_root + "/backend/qt_server.py"))
        m_root = QString::fromUtf8(FOCUS_SOURCE_DIR);
    QSettings settings;
    m_provider = settings.value("provider", "ollama").toString();
    m_model = settings.value("model", "llama3.1").toString();
    m_dark = settings.value("dark", false).toBool();
    m_network.setProxy(QNetworkProxy::NoProxy);
    m_startTimer.setSingleShot(true);
    connect(&m_startTimer, &QTimer::timeout, this, [this] {
        stop();
        setState(false, "Сервер не успел запуститься. Нажмите «Повторить запуск».");
    });
    connect(&m_process, &QProcess::started, this, [this] {
        QJsonObject config{{"provider", m_provider}, {"model", m_model},
                           {"key", m_key}, {"consent", m_consent}, {"secret", m_secret}, {"loadSaved", m_useSaved}, {"remember", m_remember}};
        m_process.write(QJsonDocument(config).toJson(QJsonDocument::Compact) + '\n');
    });
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        m_output += m_process.readAllStandardOutput();
        int end;
        while ((end = m_output.indexOf('\n')) >= 0) {
            const QByteArray line = m_output.left(end).trimmed();
            m_output.remove(0, end + 1);
            if (line.startsWith("FOCUS_READY ")) {
                bool ok = false;
                const int port = line.mid(12).toInt(&ok);
                if (ok && port > 0 && port <= 65535) {
                    m_address = QUrl(QString("http://127.0.0.1:%1").arg(port));
                    m_startTimer.stop();
                    setState(true, "Focus готов к работе");
                }
            }
        }
    });
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] { m_process.readAllStandardError(); });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (m_stopping) return;
        m_startTimer.stop();
        setState(false, error == QProcess::FailedToStart
            ? "Не удалось запустить Python. Проверьте папку runtime/python рядом с приложением."
            : "Ошибка серверного процесса. Нажмите «Повторить запуск».");
    });
    connect(&m_process, &QProcess::finished, this, [this](int, QProcess::ExitStatus) {
        if (m_stopping) return;
        m_startTimer.stop();
        setState(false, "Сервер остановлен. Нажмите «Повторить запуск».");
    });
    QTimer::singleShot(0, this, &FocusBackend::start);
}

FocusBackend::~FocusBackend() { stop(); }
void FocusBackend::setState(bool ready, const QString &status)
{ m_ready = ready; m_status = status; emit stateChanged(); }
void FocusBackend::setDark(bool dark)
{ m_dark = dark; QSettings().setValue("dark", dark); emit configurationChanged(); }
QUrl FocusBackend::assets() const { return QUrl::fromLocalFile(m_root + "/backend/web/assets/"); }
QString FocusBackend::newKey() const { return QUuid::createUuid().toString(QUuid::WithoutBraces); }
QVariantList FocusBackend::loadPinnedFeatures() const
{
    const QStringList values = QSettings().value("pinnedFeatures").toStringList();
    QVariantList result;
    for (const auto &value : values) result.append(value);
    return result;
}

void FocusBackend::savePinnedFeatures(const QVariantList &features)
{
    if (features.size() != 4) return;
    QStringList values;
    for (const auto &feature : features) values.append(feature.toString());
    QSettings().setValue("pinnedFeatures", values);
}

void FocusBackend::start()
{
    m_output.clear();
    m_secret = newKey() + newKey();
    setState(false, "Подготавливаем ваше рабочее пространство…");
    auto env = QProcessEnvironment::systemEnvironment();
    env.remove("PYTHONHOME");
    env.remove("PYTHONPATH");
    env.insert("PYTHONUTF8", "1");
    env.insert("PYTHONDONTWRITEBYTECODE", "1");
    QString dataDir = qEnvironmentVariable("FOCUS_DATA_DIR");
    if (dataDir.isEmpty()) dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(dataDir);
    env.insert("APP_DB", dataDir + "/app.sqlite3");
    m_process.setProcessEnvironment(env);
    m_process.setWorkingDirectory(m_root + "/backend");
    QString python = qEnvironmentVariable("FOCUS_PYTHON");
    if (python.isEmpty()) python = m_root + "/runtime/python/python.exe";
    m_startTimer.start(30000);
    m_process.start(python, {"-u", m_root + "/backend/qt_server.py"});
}

void FocusBackend::stop()
{
    m_stopping = true;
    ++m_generation;
    m_startTimer.stop();
    m_token.clear();
    m_ready = false;
    if (m_process.state() != QProcess::NotRunning) {
        m_process.closeWriteChannel();
        if (!m_process.waitForFinished(2000)) { m_process.kill(); m_process.waitForFinished(1000); }
    }
    m_stopping = false;
}

void FocusBackend::restart() { emit restarting(); stop(); start(); }
void FocusBackend::configure(const QString &provider, const QString &model, const QString &key, bool consent, bool remember)
{
    if (!QStringList{"ollama", "openai", "anthropic", "gemini"}.contains(provider)) return;
    m_provider = provider; m_model = model.trimmed(); m_key = key.trimmed(); m_consent = consent; m_remember = remember; m_useSaved = consent && m_key.isEmpty();
    QSettings settings;
    settings.setValue("provider", m_provider); settings.setValue("model", m_model);
    emit configurationChanged();
    restart();
}

int FocusBackend::request(const QString &path, const QVariant &body)
{
    const int id = ++m_nextId;
    const QUrl relative(path);
    if (!m_ready || !path.startsWith('/') || path.startsWith("//") || !relative.isRelative()) {
        QTimer::singleShot(0, this, [this, id] { emit response(id, {}, "Сервер ещё не готов."); });
        return id;
    }
    QNetworkRequest req(m_address.resolved(relative));
    req.setRawHeader("X-Focus-Desktop-Key", m_secret.toUtf8());
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    if (!m_token.isEmpty()) req.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
    req.setTransferTimeout(300000);
    QNetworkReply *reply;
    if (body.isValid() && !body.isNull()) {
        req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        const QVariant payload = body.metaType() == QMetaType::fromType<QJSValue>()
            ? body.value<QJSValue>().toVariant() : body;
        reply = m_network.post(req, QJsonDocument::fromVariant(payload).toJson(QJsonDocument::Compact));
    } else reply = m_network.get(req);
    const int generation = m_generation;
    connect(reply, &QNetworkReply::finished, this, [this, reply, id, generation] {
        const auto doc = QJsonDocument::fromJson(reply->readAll());
        const auto data = doc.object().toVariantMap();
        QString error;
        if (generation != m_generation) error = "Подключение перезапущено. Повторите запрос.";
        else if (reply->error() != QNetworkReply::NoError)
            error = data.value("error", "Нет связи с Focus. Повторите запрос.").toString();
        else if (!doc.isObject()) error = "Сервер вернул некорректный ответ.";
        emit response(id, data, error);
        reply->deleteLater();
    });
    return id;
}

static QString focusDataDir() {
    QString folder=qEnvironmentVariable("FOCUS_DATA_DIR");
    return folder.isEmpty() ? QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) : folder;
}
bool FocusBackend::keySaved() const { return QFileInfo::exists(focusDataDir()+"/cloud-connection.json"); }
void FocusBackend::forgetSavedConnection() {
    QFile::remove(focusDataDir()+"/cloud-connection.json");m_key.clear();m_useSaved=false;m_consent=false;
    emit configurationChanged();restart();
}
bool FocusBackend::saveArtifact(const QUrl &path,const QString &content) {
    if (!path.isLocalFile()) return false;
    const QByteArray bytes=QByteArray::fromBase64(content.toLatin1());
    if(bytes.isEmpty() || bytes.size()>20000000) return false;
    QSaveFile file(path.toLocalFile());
    if(!file.open(QIODevice::WriteOnly) || file.write(bytes)!=bytes.size() || !file.commit()) { emit featureError("Не удалось сохранить файл");return false; }
    return true;
}
bool FocusBackend::exportPdf(const QUrl &path,const QString &title,const QVariantList &rows) {
    if(!path.isLocalFile() || rows.size()>1000)return false;
    QSaveFile file(path.toLocalFile());if(!file.open(QIODevice::WriteOnly))return false;
    {
        QPdfWriter writer(&file);writer.setPageSize(QPageSize(QPageSize::A4));writer.setResolution(96);writer.setTitle(title);
        QPainter painter(&writer);if(!painter.isActive())return false;
        const int width=writer.width(),height=writer.height();int y=28;
        painter.setPen(QColor("#29243a"));painter.setFont(QFont("Segoe UI",20,QFont::DemiBold));
        painter.drawText(QRect(24,y,width-48,70),Qt::TextWordWrap,title);y+=85;
        painter.setFont(QFont("Segoe UI",10));
        for(const auto &value:rows){
            const auto row=value.toMap();const QString text=row.value("title").toString()+"\n"+row.value("detail").toString();
            const int block=qMin(500,painter.fontMetrics().boundingRect(QRect(0,0,width-64,10000),Qt::TextWordWrap,text).height()+26);
            if(y+block>height-24){writer.newPage();y=24;}
            painter.setPen(QColor("#e0daed"));painter.drawLine(24,y,width-24,y);
            painter.setPen(QColor("#29243a"));painter.drawText(QRect(32,y+10,width-64,block-16),Qt::TextWordWrap,text);y+=block;
        }
        painter.end();
    }
    return file.commit();
}
QUrl FocusBackend::startMeetingRecording() {
    if(recording())return m_recordedPath;
    if(QMediaDevices::defaultAudioInput().isNull()){emit featureError("Микрофон не найден. Можно выбрать готовую запись.");return {};}
    if(!m_audioInput){
        m_audioInput=new QAudioInput(this);m_capture.setAudioInput(m_audioInput);m_capture.setRecorder(&m_recorder);
        connect(&m_recorder,&QMediaRecorder::recorderStateChanged,this,[this](QMediaRecorder::RecorderState state){emit recordingChanged();if(state==QMediaRecorder::StoppedState)QTimer::singleShot(250,this,[this]{emit recordingSaved(m_recordedPath);});});
        connect(&m_recorder,&QMediaRecorder::errorOccurred,this,[this](QMediaRecorder::Error,const QString &){emit featureError("Не удалось записать звук. Проверьте микрофон и разрешения Windows.");});
    }
    const QString dir=focusDataDir()+"/recordings";QDir().mkpath(dir);
    m_recordedPath=QUrl::fromLocalFile(dir+"/"+newKey()+".m4a");
    QMediaFormat format(QMediaFormat::MPEG4);format.setAudioCodec(QMediaFormat::AudioCodec::AAC);m_recorder.setMediaFormat(format);
    m_recorder.setOutputLocation(m_recordedPath);m_recorder.setAudioSampleRate(16000);m_recorder.setAudioBitRate(64000);m_recorder.record();return m_recordedPath;
}
void FocusBackend::stopMeetingRecording(){m_recorder.stop();}
