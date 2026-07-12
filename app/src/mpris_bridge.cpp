#include "mpris_bridge.h"

#include <QDebug>
#include <QFileInfo>
#include <QStringList>
#include <QUrl>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>
#include <QtDBus/QDBusVariant>

static const char* kPath = "/org/mpris/MediaPlayer2";
static const char* kPlayerIface = "org.mpris.MediaPlayer2.Player";
static const char* kPropsIface = "org.freedesktop.DBus.Properties";
static const QString kPrefix = QStringLiteral("org.mpris.MediaPlayer2.");

// All reads run on the GUI thread, so cap how long an unresponsive player can
// stall us. The default D-Bus timeout is 25s; a hung player would freeze the UI
// for that long. 800ms is generous for a healthy player (which replies in <10ms)
// while keeping any stall imperceptible. Building calls with
// QDBusMessage::createMethodCall (instead of QDBusInterface) also avoids a
// blocking introspection round-trip on every single call.
static constexpr int kDbusTimeoutMs = 800;

// Helper: Properties.Get(iface, prop) → unwrapped variant. Invalid on failure.
static QVariant propGet(const QDBusConnection& bus, const QString& service,
                        const QString& iface, const QString& prop) {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        service, QString::fromLatin1(kPath), QString::fromLatin1(kPropsIface),
        QStringLiteral("Get"));
    msg << iface << prop;
    const QDBusMessage reply = bus.call(msg, QDBus::Block, kDbusTimeoutMs);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return QVariant();
    return reply.arguments().first().value<QDBusVariant>().variant();
}

MprisBridge::MprisBridge(QObject* parent)
    : QObject(parent), m_bus(QDBusConnection::sessionBus()) {
    // Re-scan for players periodically (they come and go); poll position faster.
    m_rescan.setInterval(3000);
    connect(&m_rescan, &QTimer::timeout, this, &MprisBridge::reevaluate);
    m_rescan.start();

    m_poll.setInterval(1000);
    connect(&m_poll, &QTimer::timeout, this, &MprisBridge::poll);
    m_poll.start();

    reevaluate();
}

QStringList MprisBridge::mprisServices() const {
    QStringList out;
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("ListNames"));
    const QDBusMessage reply = m_bus.call(msg, QDBus::Block, kDbusTimeoutMs);
    if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
        const QStringList names = reply.arguments().first().toStringList();
        for (const QString& name : names)
            if (name.startsWith(kPrefix))
                out << name;
    }
    return out;
}

QString MprisBridge::statusOf(const QString& service) const {
    return propGet(m_bus, service, QString::fromLatin1(kPlayerIface),
                   QStringLiteral("PlaybackStatus"))
        .toString();
}

void MprisBridge::reevaluate() {
    const QStringList services = mprisServices();
    if (services.isEmpty()) {
        if (m_available || !m_service.isEmpty()) {
            connectTo(QString());
        }
        return;
    }

    // Prefer a player that is currently Playing; else keep the current one if
    // still present; else the first available.
    QString chosen;
    for (const QString& s : services) {
        if (statusOf(s) == QStringLiteral("Playing")) { chosen = s; break; }
    }
    if (chosen.isEmpty())
        chosen = services.contains(m_service) ? m_service : services.first();

    if (chosen != m_service)
        connectTo(chosen);
    else
        refresh();
}

void MprisBridge::connectTo(const QString& service) {
    if (!m_service.isEmpty()) {
        m_bus.disconnect(m_service, kPath, kPropsIface, QStringLiteral("PropertiesChanged"),
                         this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    }
    m_service = service;
    if (!m_service.isEmpty()) {
        m_bus.connect(m_service, kPath, kPropsIface, QStringLiteral("PropertiesChanged"),
                      this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    }
    refresh();
}

void MprisBridge::onPropertiesChanged(const QString&, const QVariantMap&, const QStringList&) {
    refresh();
}

void MprisBridge::refresh() {
    if (m_service.isEmpty()) {
        if (m_available) {
            m_available = false;
            m_title = m_artist = m_album = m_artUrl = m_status = m_playerName = QString();
            m_lengthUs = m_positionUs = 0;
            emit changed();
        }
        return;
    }

    QDBusMessage getAll = QDBusMessage::createMethodCall(
        m_service, QString::fromLatin1(kPath), QString::fromLatin1(kPropsIface),
        QStringLiteral("GetAll"));
    getAll << QString::fromLatin1(kPlayerIface);
    const QDBusMessage allReply = m_bus.call(getAll, QDBus::Block, kDbusTimeoutMs);
    if (allReply.type() != QDBusMessage::ReplyMessage || allReply.arguments().isEmpty()) {
        m_available = false;
        emit changed();
        return;
    }
    const QVariantMap m = qdbus_cast<QVariantMap>(allReply.arguments().first());
    m_status = m.value(QStringLiteral("PlaybackStatus")).toString();

    const QVariantMap meta = qdbus_cast<QVariantMap>(m.value(QStringLiteral("Metadata")));
    m_title = meta.value(QStringLiteral("xesam:title")).toString();
    QStringList artists = qdbus_cast<QStringList>(meta.value(QStringLiteral("xesam:artist")));
    if (artists.isEmpty())
        artists = meta.value(QStringLiteral("xesam:artist")).toStringList();
    m_artist = artists.join(QStringLiteral(", "));
    m_album = meta.value(QStringLiteral("xesam:album")).toString();
    m_artUrl = meta.value(QStringLiteral("mpris:artUrl")).toString();
    // Some players (e.g. Chromium) advertise a file:// art path that may be
    // stale/unreadable. Validate local files so QML never tries a bad URL
    // (which would emit an Image "Cannot open" warning); http(s) is passed through.
    if (m_artUrl.startsWith(QStringLiteral("file://"))) {
        const QString local = QUrl(m_artUrl).toLocalFile();
        if (local.isEmpty() || !QFileInfo(local).isReadable())
            m_artUrl.clear();
    }
    m_lengthUs = meta.value(QStringLiteral("mpris:length")).toLongLong();
    m_playerName = m_service.mid(kPrefix.length());

    const QVariant posV =
        propGet(m_bus, m_service, QString::fromLatin1(kPlayerIface), QStringLiteral("Position"));
    if (posV.isValid())
        m_positionUs = posV.toLongLong();

    // A service can be registered on the bus (CanControl: true) with no track
    // actually loaded — e.g. a browser tab with audio capability but nothing
    // played yet, or a player that was just stopped. Treat that as genuinely
    // "nothing playing" rather than showing a blank card: require either a
    // real title or an active Playing/Paused status.
    const bool hasTrack = !m_title.isEmpty();
    const bool isActive = m_status == QStringLiteral("Playing") || m_status == QStringLiteral("Paused");
    m_available = hasTrack || isActive;
    if (!m_available) {
        m_title = m_artist = m_album = m_artUrl = QString();
        m_lengthUs = 0;
    }
    emit changed();
    emit positionChanged();
}

void MprisBridge::poll() {
    if (!m_available || m_service.isEmpty() || m_status != QStringLiteral("Playing"))
        return;
    const QVariant posV =
        propGet(m_bus, m_service, QString::fromLatin1(kPlayerIface), QStringLiteral("Position"));
    if (posV.isValid()) {
        m_positionUs = posV.toLongLong();
        emit positionChanged();
    }
}

void MprisBridge::callPlayer(const char* method) {
    if (m_service.isEmpty())
        return;
    // Fire-and-forget: transport controls must never block the GUI thread.
    QDBusMessage msg = QDBusMessage::createMethodCall(
        m_service, QString::fromLatin1(kPath), QString::fromLatin1(kPlayerIface),
        QString::fromLatin1(method));
    m_bus.asyncCall(msg);
    // Reflect the new state promptly.
    QTimer::singleShot(200, this, [this] { refresh(); });
}

void MprisBridge::playPause() { callPlayer("PlayPause"); }
void MprisBridge::next() { callPlayer("Next"); }
void MprisBridge::previous() { callPlayer("Previous"); }
