#include "mpris_bridge.h"

#include <QDebug>
#include <QFileInfo>
#include <QStringList>
#include <QUrl>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>

static const char* kPath = "/org/mpris/MediaPlayer2";
static const char* kPlayerIface = "org.mpris.MediaPlayer2.Player";
static const char* kPropsIface = "org.freedesktop.DBus.Properties";
static const QString kPrefix = QStringLiteral("org.mpris.MediaPlayer2.");

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
    QDBusInterface dbus(QStringLiteral("org.freedesktop.DBus"),
                        QStringLiteral("/org/freedesktop/DBus"),
                        QStringLiteral("org.freedesktop.DBus"), m_bus);
    QDBusReply<QStringList> reply = dbus.call(QStringLiteral("ListNames"));
    if (reply.isValid()) {
        for (const QString& name : reply.value())
            if (name.startsWith(kPrefix))
                out << name;
    }
    return out;
}

QString MprisBridge::statusOf(const QString& service) const {
    QDBusInterface props(service, kPath, kPropsIface, m_bus);
    QDBusReply<QDBusVariant> r =
        props.call(QStringLiteral("Get"), QString(kPlayerIface), QStringLiteral("PlaybackStatus"));
    return r.isValid() ? r.value().variant().toString() : QString();
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

    QDBusInterface props(m_service, kPath, kPropsIface, m_bus);
    QDBusReply<QVariantMap> all = props.call(QStringLiteral("GetAll"), QString(kPlayerIface));
    if (!all.isValid()) {
        m_available = false;
        emit changed();
        return;
    }
    const QVariantMap m = all.value();
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

    QDBusReply<QDBusVariant> posR =
        props.call(QStringLiteral("Get"), QString(kPlayerIface), QStringLiteral("Position"));
    if (posR.isValid())
        m_positionUs = posR.value().variant().toLongLong();

    m_available = true;
    emit changed();
    emit positionChanged();
}

void MprisBridge::poll() {
    if (!m_available || m_service.isEmpty() || m_status != QStringLiteral("Playing"))
        return;
    QDBusInterface props(m_service, kPath, kPropsIface, m_bus);
    QDBusReply<QDBusVariant> posR =
        props.call(QStringLiteral("Get"), QString(kPlayerIface), QStringLiteral("Position"));
    if (posR.isValid()) {
        m_positionUs = posR.value().variant().toLongLong();
        emit positionChanged();
    }
}

void MprisBridge::callPlayer(const char* method) {
    if (m_service.isEmpty())
        return;
    QDBusInterface player(m_service, kPath, kPlayerIface, m_bus);
    player.call(QString::fromLatin1(method));
    // Reflect the new state promptly.
    QTimer::singleShot(150, this, [this] { refresh(); });
}

void MprisBridge::playPause() { callPlayer("PlayPause"); }
void MprisBridge::next() { callPlayer("Next"); }
void MprisBridge::previous() { callPlayer("Previous"); }
