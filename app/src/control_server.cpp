#include "control_server.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>

// Well-known socket name. QLocalServer places it under $XDG_RUNTIME_DIR on
// Linux, so it is per-user and does not touch the filesystem tree.
static const char* kSocketName = "xeneon-edge-hub-ctl";

ControlServer::ControlServer(QObject* parent) : QObject(parent) {}

ControlServer::~ControlServer() {
    if (m_server)
        m_server->close();
}

bool ControlServer::start() {
    // Clear any stale socket left by a previous crashed instance.
    QLocalServer::removeServer(kSocketName);

    m_server = new QLocalServer(this);
    // Restrict to the current user.
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server->listen(kSocketName)) {
        qWarning() << "ControlServer: failed to listen on" << kSocketName << ":"
                   << m_server->errorString();
        return false;
    }
    connect(m_server, &QLocalServer::newConnection, this, &ControlServer::onNewConnection);
    qInfo() << "ControlServer listening on" << kSocketName;
    return true;
}

void ControlServer::onNewConnection() {
    while (m_server->hasPendingConnections()) {
        QLocalSocket* sock = m_server->nextPendingConnection();
        m_buffers.insert(sock, QByteArray());
        connect(sock, &QLocalSocket::readyRead, this, &ControlServer::onReadyRead);
        connect(sock, &QLocalSocket::disconnected, this, &ControlServer::onDisconnected);
    }
}

void ControlServer::onReadyRead() {
    QLocalSocket* sock = qobject_cast<QLocalSocket*>(sender());
    if (!sock)
        return;
    // Look the buffer up (don't operator[]-insert): if the socket was already
    // torn down by the oversized/disconnect path, there's nothing to append to.
    auto it = m_buffers.find(sock);
    if (it == m_buffers.end())
        return;
    it.value().append(sock->readAll());
    // Cap the buffer so a misbehaving client can't grow it unbounded.
    if (it.value().size() > 8 * 1024 * 1024) {
        qWarning() << "ControlServer: oversized message, dropping connection";
        // abort() may not emit disconnected(), so free the buffer entry here.
        m_buffers.remove(sock);
        sock->abort();
        sock->deleteLater();
        return;
    }
    // Process complete lines. Re-look up the buffer each iteration and splice the
    // line out of it BEFORE dispatching: handleLine() can re-enter the event loop
    // (writeJson()'s flush, or a slot on uiStateReceived that reloads the UI) and
    // erase this socket's entry, so any reference into m_buffers held across the
    // callback could dangle. `line` is an independent copy, safe to pass along.
    while (true) {
        auto bit = m_buffers.find(sock);
        if (bit == m_buffers.end())
            return;   // socket was torn down by a previous dispatch
        const int nl = bit.value().indexOf('\n');
        if (nl < 0)
            break;
        const QByteArray line = bit.value().left(nl);
        bit.value().remove(0, nl + 1);
        if (!line.trimmed().isEmpty())
            handleLine(sock, line);
    }
}

void ControlServer::onDisconnected() {
    QLocalSocket* sock = qobject_cast<QLocalSocket*>(sender());
    if (!sock)
        return;
    m_buffers.remove(sock);
    sock->deleteLater();
}

void ControlServer::handleLine(QLocalSocket* sock, const QByteArray& line) {
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(line, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        writeJson(sock, QJsonDocument(QJsonObject{{"type", "error"},
                                                  {"message", "invalid json"}})
                            .toJson(QJsonDocument::Compact));
        return;
    }
    const QJsonObject obj = doc.object();
    const QString type = obj.value("type").toString();

    if (type == "getUiState") {
        const QString state = m_provider ? m_provider() : QString();
        writeJson(sock, QJsonDocument(QJsonObject{{"type", "uiState"}, {"state", state}})
                            .toJson(QJsonDocument::Compact));
    } else if (type == "setUiState") {
        const QString state = obj.value("state").toString();
        if (state.isEmpty()) {
            writeJson(sock, QJsonDocument(QJsonObject{{"type", "error"},
                                                      {"message", "empty state"}})
                                .toJson(QJsonDocument::Compact));
            return;
        }
        // Let the owner apply the state and report whether it stuck. The signal is
        // delivered synchronously (same-thread direct connection), so `ok` holds
        // the real result once emit returns — the ack must reflect it, otherwise
        // the Manager treats a failed persist as success and silently diverges.
        bool ok = false;
        emit uiStateReceived(state, &ok);
        if (ok) {
            writeJson(sock,
                      QJsonDocument(QJsonObject{{"type", "ok"}}).toJson(QJsonDocument::Compact));
        } else {
            writeJson(sock, QJsonDocument(QJsonObject{{"type", "error"},
                                                      {"message", "failed to apply state"}})
                                .toJson(QJsonDocument::Compact));
        }
    } else if (type == "ping") {
        writeJson(sock, QJsonDocument(QJsonObject{{"type", "pong"}}).toJson(QJsonDocument::Compact));
    } else if (type == "shutdown") {
        // The companion Manager asked the hub to quit cleanly (Start/Stop control).
        // Ack first so the client sees it, then let main() quit gracefully (which
        // persists config + tears down normally).
        writeJson(sock, QJsonDocument(QJsonObject{{"type", "ok"}}).toJson(QJsonDocument::Compact));
        emit shutdownRequested();
    } else {
        writeJson(sock, QJsonDocument(QJsonObject{{"type", "error"},
                                                  {"message", "unknown type"}})
                            .toJson(QJsonDocument::Compact));
    }
}

void ControlServer::writeJson(QLocalSocket* sock, const QByteArray& compactJson) {
    if (!sock || sock->state() != QLocalSocket::ConnectedState)
        return;
    sock->write(compactJson);
    sock->write("\n");
    sock->flush();
}
