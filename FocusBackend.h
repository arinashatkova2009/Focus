#pragma once
#include <QObject>
#include <QProcess>
#include <QNetworkAccessManager>
#include <QTimer>
#include <QVariantMap>
#include <QUrl>
#include <QMediaCaptureSession>
#include <QAudioInput>
#include <QMediaRecorder>
#include <QtQml/qqmlregistration.h>

class FocusBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool ready READ ready NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(QString provider READ provider NOTIFY configurationChanged)
    Q_PROPERTY(QString model READ model NOTIFY configurationChanged)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY configurationChanged)
    Q_PROPERTY(QUrl assets READ assets CONSTANT)
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(bool keySaved READ keySaved NOTIFY configurationChanged)
public:
    explicit FocusBackend(QObject *parent = nullptr);
    ~FocusBackend() override;
    bool ready() const { return m_ready; }
    QString status() const { return m_status; }
    QString provider() const { return m_provider; }
    QString model() const { return m_model; }
    bool dark() const { return m_dark; }
    void setDark(bool dark);
    QUrl assets() const;
    bool recording() const { return m_recorder.recorderState() == QMediaRecorder::RecordingState; }
    bool keySaved() const;
    Q_INVOKABLE bool saveArtifact(const QUrl &path, const QString &content);
    Q_INVOKABLE bool exportPdf(const QUrl &path, const QString &title, const QVariantList &rows);
    Q_INVOKABLE QUrl startMeetingRecording();
    Q_INVOKABLE void stopMeetingRecording();
    Q_INVOKABLE void forgetSavedConnection();
    Q_INVOKABLE int request(const QString &path, const QVariant &body = QVariant());
    Q_INVOKABLE void setToken(const QString &token) { m_token = token; }
    Q_INVOKABLE QString newKey() const;
    Q_INVOKABLE QVariantList loadPinnedFeatures() const;
    Q_INVOKABLE void savePinnedFeatures(const QVariantList &features);
    Q_INVOKABLE void configure(const QString &provider, const QString &model,
                              const QString &key, bool consent, bool remember = false);
    Q_INVOKABLE void restart();
signals:
    void stateChanged();
    void configurationChanged();
    void response(int id, const QVariantMap &data, const QString &error);
    void restarting();
    void featureError(const QString &message);
    void recordingChanged();
    void recordingSaved(const QUrl &path);
private:
    void start();
    void stop();
    void setState(bool ready, const QString &status);
    QMediaCaptureSession m_capture;
    QMediaRecorder m_recorder;
    QAudioInput *m_audioInput = nullptr;
    QUrl m_recordedPath;
    bool m_useSaved = true, m_remember = false;
    QProcess m_process;
    QNetworkAccessManager m_network;
    QTimer m_startTimer;
    QString m_root, m_status, m_token, m_provider, m_model, m_key, m_secret;
    QByteArray m_output;
    QUrl m_address;
    bool m_ready = false, m_dark = false, m_consent = false, m_stopping = false;
    int m_nextId = 0, m_generation = 0;
};
