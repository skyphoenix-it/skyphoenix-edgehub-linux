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
// domain socket whose path comes from app/src/control_socket_path.h — shared
// with the Manager's client, since the two must agree) and speaks
// newline-delimited JSON:
//
//   → {"type":"getUiState"}                      (client asks for current layout)
//   ← {"type":"uiState","state":"<ui_state json>"}
//   → {"type":"setUiState","state":"<ui_state json>"}   (client pushes a new layout)
//   → {"type":"setTargetDisplay","connector":"DP-3","model":"XENEON EDGE"}
//   ← {"type":"ok","for":"setTargetDisplay"} | {"type":"error","for":…,"message":…}
//   → {"type":"setAutostart","enabled":true}
//   ← {"type":"ok","for":"setAutostart"}     | {"type":"error","for":…,"message":…}
//
// On setUiState the server emits uiStateReceived() so main() can persist it and
// reload the live dashboard. Connection is optional: the manager also writes the
// shared config directly, so it works whether or not the hub is running.
//
// The per-field setters exist because config.toml must have exactly ONE writer.
// While the hub runs it owns the file, so a client that wrote a field directly
// would have it reverted by the hub's next save (whose in-memory config never saw
// the change). Each setter is per-field rather than a blunt "reloadConfig" so the
// hub adopts the value into its LIVE config and applies its side effect — a reload
// of a file the hub itself is about to overwrite would just move the race.
//
// The acks for the per-field setters carry "for" (the request type) so a client can
// match a reply to its request; the older setUiState/shutdown acks stay untagged.
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
    // The current content rotation (0/90/180/270, or -1 unknown), so the getUiState
    // reply can carry it and a connected Manager can mirror the panel's live
    // orientation in its preview. Optional: with no provider the field is omitted
    // and the reply is unchanged (older/other clients ignore it).
    void setRotationProvider(const std::function<int()>& provider) { m_rotationProvider = provider; }

signals:
    // A client pushed a new UI-state document; main persists + reloads it and
    // writes the apply result back through `ok` (an out-parameter, since a signal
    // can't return a value) so setUiState can ack success/failure honestly. The
    // slot is same-thread, so the value is set by the time emit returns.
    void uiStateReceived(const QString& json, bool* ok);
    // A client asked the hub to adopt a new target display / autostart preference.
    // Same contract as uiStateReceived: `ok` is an out-parameter written by a
    // same-thread (direct) slot before emit returns, so the ack is honest.
    void targetDisplayReceived(const QString& connector, const QString& model, bool* ok);
    void autostartReceived(bool enabled, bool* ok);
    // A Pro licence key pushed from the Manager. `ok` reports whether the hub
    // persisted it (same synchronous-ack discipline as uiStateReceived).
    void licenseKeyReceived(const QString& key, bool* ok);
    // A client asked the hub to quit (companion Manager's Stop control).
    void shutdownRequested();

private slots:
    void onNewConnection();
    void onReadyRead();
    void onDisconnected();

private:
    void handleLine(QLocalSocket* sock, const QByteArray& line);
    // Reply to a per-field setter: {"type":"ok"|"error","for":<forType>[,"message"]}.
    static void writeAck(QLocalSocket* sock, bool ok, const QString& forType,
                         const QString& failMessage);
    static void writeJson(QLocalSocket* sock, const QByteArray& compactJson);

    QLocalServer* m_server = nullptr;
    QHash<QLocalSocket*, QByteArray> m_buffers;   // per-connection read buffer
    std::function<QString()> m_provider;
    std::function<int()> m_rotationProvider;
};

#endif // CONTROL_SERVER_H
