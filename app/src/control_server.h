#ifndef CONTROL_SERVER_H
#define CONTROL_SERVER_H

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QString>

#include <functional>

class QLocalServer;
class QLocalSocket;

// ControlServer — a local IPC endpoint that lets the companion "Xeneon Edge
// Manager" app drive the running hub live. It listens on a QLocalServer (a Unix
// domain socket under $XDG_RUNTIME_DIR) and speaks newline-delimited JSON:
//
//   → {"type":"getUiState"}                      (client asks for current layout)
//   ← {"type":"uiState","state":"<ui_state json>"}
//   → {"type":"setUiState","state":"<ui_state json>"}   (client pushes a new layout)
//
// On setUiState the server emits uiStateReceived() so main() can persist it and
// reload the live dashboard. Connection is optional: the manager also writes the
// shared config directly, so it works whether or not the hub is running.
class ControlServer : public QObject {
    Q_OBJECT
public:
    explicit ControlServer(QObject* parent = nullptr);
    ~ControlServer() override;

    // Begin listening. Returns false if the socket could not be created.
    bool start();

    // The current UI-state JSON, supplied by the owner (main) so the server can
    // answer getUiState without depending on the config layer directly.
    void setStateProvider(const std::function<QString()>& provider) { m_provider = provider; }

signals:
    // A client pushed a new UI-state document; main persists + reloads it and
    // writes the apply result back through `ok` (an out-parameter, since a signal
    // can't return a value) so setUiState can ack success/failure honestly. The
    // slot is same-thread, so the value is set by the time emit returns.
    void uiStateReceived(const QString& json, bool* ok);
    // A client asked the hub to quit (companion Manager's Stop control).
    void shutdownRequested();

private slots:
    void onNewConnection();
    void onReadyRead();
    void onDisconnected();

private:
    void handleLine(QLocalSocket* sock, const QByteArray& line);
    static void writeJson(QLocalSocket* sock, const QByteArray& compactJson);

    QLocalServer* m_server = nullptr;
    QHash<QLocalSocket*, QByteArray> m_buffers;   // per-connection read buffer
    std::function<QString()> m_provider;
};

#endif // CONTROL_SERVER_H
