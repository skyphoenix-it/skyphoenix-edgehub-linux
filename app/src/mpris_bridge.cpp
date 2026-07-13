#include "mpris_bridge.h"

#include <QDebug>
#include <QFileInfo>
#include <QMap>
#include <QSharedPointer>
#include <QStringList>
#include <QUrl>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>
#include <QtDBus/QDBusPendingCallWatcher>
#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusVariant>

static const char* kPath = "/org/mpris/MediaPlayer2";
static const char* kPlayerIface = "org.mpris.MediaPlayer2.Player";
static const char* kPropsIface = "org.freedesktop.DBus.Properties";
static const QString kPrefix = QStringLiteral("org.mpris.MediaPlayer2.");

// Cap on how long a D-Bus call may take before erroring. Every call here is
// ASYNC, so this bounds a hung player's reply latency without ever blocking the
// GUI thread (the old code used QDBus::Block up to 800ms, which could stack up
// to (N+1)×800ms of stall across a rescan). Building calls with createMethodCall
// (not QDBusInterface) also avoids a blocking introspection round-trip.
static constexpr int kDbusTimeoutMs = 800;

// Build a Properties.Get(iface, prop) call message.
static QDBusMessage propGetMsg(const QString& service, const QString& iface, const QString& prop) {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        service, QString::fromLatin1(kPath), QString::fromLatin1(kPropsIface),
        QStringLiteral("Get"));
    msg << iface << prop;
    return msg;
}

MprisBridge::MprisBridge(QObject* parent)
    : QObject(parent), m_bus(QDBusConnection::sessionBus()) {
    if (!m_bus.isConnected()) {
        qWarning() << "MprisBridge: no session D-Bus connection; media controls disabled";
        return;   // leave the timers stopped → stays permanently unavailable
    }
    // Re-scan for players periodically (they come and go); poll position faster.
    m_rescan.setInterval(3000);
    connect(&m_rescan, &QTimer::timeout, this, &MprisBridge::reevaluate);
    m_rescan.start();

    m_poll.setInterval(1000);
    connect(&m_poll, &QTimer::timeout, this, &MprisBridge::poll);
    m_poll.start();

    reevaluate();
}

MprisBridge::~MprisBridge() {
    // Drop the PropertiesChanged match rule on the shared session bus so it
    // doesn't linger after we're gone.
    if (!m_service.isEmpty()) {
        m_bus.disconnect(m_service, kPath, kPropsIface, QStringLiteral("PropertiesChanged"),
                         this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    }
}

// (Re)pick the active player: async ListNames → filter to MPRIS services.
void MprisBridge::reevaluate() {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("ListNames"));
    auto* w = new QDBusPendingCallWatcher(m_bus.asyncCall(msg, kDbusTimeoutMs), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* self) {
        self->deleteLater();
        QDBusPendingReply<QStringList> reply = *self;
        QStringList services;
        if (reply.isValid()) {
            for (const QString& name : reply.value())
                if (name.startsWith(kPrefix))
                    services << name;
        }
        chooseFrom(services);
    });
}

// Given the current MPRIS services, prefer one that is Playing, else keep the
// current one if still present, else the first. The PlaybackStatus probe is an
// async fan-out that decides once all replies are in.
void MprisBridge::chooseFrom(const QStringList& services) {
    if (services.isEmpty()) {
        if (m_available || !m_service.isEmpty())
            connectTo(QString());
        return;
    }
    auto order = QSharedPointer<QStringList>::create(services);
    auto statuses = QSharedPointer<QMap<QString, QString>>::create();
    auto remaining = QSharedPointer<int>::create(services.size());
    for (const QString& s : services) {
        QDBusMessage msg = propGetMsg(s, QString::fromLatin1(kPlayerIface),
                                      QStringLiteral("PlaybackStatus"));
        auto* w = new QDBusPendingCallWatcher(m_bus.asyncCall(msg, kDbusTimeoutMs), this);
        connect(w, &QDBusPendingCallWatcher::finished, this,
                [this, s, order, statuses, remaining](QDBusPendingCallWatcher* self) {
            self->deleteLater();
            QDBusPendingReply<QDBusVariant> reply = *self;
            statuses->insert(s, reply.isValid() ? reply.value().variant().toString() : QString());
            if (--(*remaining) != 0)
                return;
            QString chosen;
            for (const QString& cand : *order)
                if (statuses->value(cand) == QStringLiteral("Playing")) { chosen = cand; break; }
            if (chosen.isEmpty())
                chosen = order->contains(m_service) ? m_service : order->first();
            if (chosen != m_service)
                connectTo(chosen);
            else
                refresh();
        });
    }
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

// GetAll the player props (async), apply them, then fetch Position (async).
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
    // Capture the service this reply belongs to. If the active player switched
    // while the async call was in flight, a late reply from the OLD player must
    // NOT overwrite the new one's metadata.
    const QString service = m_service;
    auto* w = new QDBusPendingCallWatcher(m_bus.asyncCall(getAll, kDbusTimeoutMs), this);
    connect(w, &QDBusPendingCallWatcher::finished, this,
            [this, service](QDBusPendingCallWatcher* self) {
        self->deleteLater();
        if (service != m_service)
            return;   // player changed since we asked; drop the stale reply
        QDBusPendingReply<QVariantMap> reply = *self;
        if (!reply.isValid()) {
            if (m_available) { m_available = false; emit changed(); }
            return;
        }
        applyProps(reply.value());
        fetchPosition();
    });
}

void MprisBridge::applyProps(const QVariantMap& m) {
    // Compute the new values into locals first so we can dirty-check against the
    // current state and only notify QML when something actually moved (see below).
    QString status = m.value(QStringLiteral("PlaybackStatus")).toString();

    const QVariantMap meta = qdbus_cast<QVariantMap>(m.value(QStringLiteral("Metadata")));
    QString title = meta.value(QStringLiteral("xesam:title")).toString();
    QStringList artists = qdbus_cast<QStringList>(meta.value(QStringLiteral("xesam:artist")));
    if (artists.isEmpty())
        artists = meta.value(QStringLiteral("xesam:artist")).toStringList();
    QString artist = artists.join(QStringLiteral(", "));
    QString album = meta.value(QStringLiteral("xesam:album")).toString();
    QString artUrl = meta.value(QStringLiteral("mpris:artUrl")).toString();
    // Some players (e.g. Chromium) advertise a file:// art path that may be
    // stale/unreadable. Validate local files so QML never tries a bad URL
    // (which would emit an Image "Cannot open" warning); http(s) is passed through.
    if (artUrl.startsWith(QStringLiteral("file://"))) {
        const QString local = QUrl(artUrl).toLocalFile();
        if (local.isEmpty() || !QFileInfo(local).isReadable())
            artUrl.clear();
    }
    qlonglong lengthUs = meta.value(QStringLiteral("mpris:length")).toLongLong();
    QString playerName = m_service.mid(kPrefix.length());

    // A service can be registered on the bus (CanControl: true) with no track
    // actually loaded — e.g. a browser tab with audio capability but nothing
    // played yet, or a player that was just stopped. Treat that as genuinely
    // "nothing playing" rather than showing a blank card: require either a real
    // title or an active Playing/Paused status.
    const bool hasTrack = !title.isEmpty();
    const bool isActive = status == QStringLiteral("Playing") || status == QStringLiteral("Paused");
    bool available = hasTrack || isActive;
    if (!available) {
        title = artist = album = artUrl = QString();
        lengthUs = 0;
    }

    // Dirty-check: applyProps runs on every 3s rescan, but emitting changed()
    // unconditionally re-fires every property NOTIFY and restarts QML animations
    // bound to them. Only emit when a visible field really changed.
    const bool dirty = available != m_available || status != m_status ||
                       title != m_title || artist != m_artist || album != m_album ||
                       artUrl != m_artUrl || playerName != m_playerName;

    m_status = status;
    m_title = title;
    m_artist = artist;
    m_album = album;
    m_artUrl = artUrl;
    m_lengthUs = lengthUs;
    m_playerName = playerName;
    m_available = available;

    if (dirty)
        emit changed();
}

void MprisBridge::fetchPosition() {
    if (m_service.isEmpty())
        return;
    QDBusMessage msg = propGetMsg(m_service, QString::fromLatin1(kPlayerIface),
                                  QStringLiteral("Position"));
    // Same identity guard as refresh(): a Position reply from a player we've since
    // switched away from must not scrub the new player's position.
    const QString service = m_service;
    auto* w = new QDBusPendingCallWatcher(m_bus.asyncCall(msg, kDbusTimeoutMs), this);
    connect(w, &QDBusPendingCallWatcher::finished, this,
            [this, service](QDBusPendingCallWatcher* self) {
        self->deleteLater();
        if (service != m_service)
            return;   // stale reply from a replaced player; drop it
        QDBusPendingReply<QDBusVariant> reply = *self;
        if (reply.isValid()) {
            m_positionUs = reply.value().variant().toLongLong();
            emit positionChanged();
        }
    });
}

void MprisBridge::poll() {
    if (!m_available || m_service.isEmpty() || m_status != QStringLiteral("Playing"))
        return;
    fetchPosition();
}

void MprisBridge::callPlayer(const char* method) {
    if (m_service.isEmpty())
        return;
    // Fire-and-forget transport control (never blocks the GUI thread), but log a
    // failed call so a broken PlayPause/Next/Previous isn't entirely invisible.
    QDBusMessage msg = QDBusMessage::createMethodCall(
        m_service, QString::fromLatin1(kPath), QString::fromLatin1(kPlayerIface),
        QString::fromLatin1(method));
    auto* w = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    const QString methodName = QString::fromLatin1(method);
    connect(w, &QDBusPendingCallWatcher::finished, this,
            [methodName](QDBusPendingCallWatcher* self) {
        self->deleteLater();
        QDBusPendingReply<> reply = *self;
        if (reply.isError())
            qWarning() << "MprisBridge:" << methodName << "failed:" << reply.error().message();
    });
    // Reflect the new state promptly.
    QTimer::singleShot(200, this, [this] { refresh(); });
}

void MprisBridge::playPause() { callPlayer("PlayPause"); }
void MprisBridge::next() { callPlayer("Next"); }
void MprisBridge::previous() { callPlayer("Previous"); }
