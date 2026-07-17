#include "mpris_state.h"

#include <QFileInfo>
#include <QUrl>
#include <QtDBus/QDBusArgument>   // qdbus_cast

namespace {
const QString kPrefix = QStringLiteral("org.mpris.MediaPlayer2.");
}

namespace mpris {

bool isMprisService(const QString& busName) { return busName.startsWith(kPrefix); }

QString playerNameFromService(const QString& service) { return service.mid(kPrefix.length()); }

QString choosePlayer(const QStringList& order, const QMap<QString, QString>& statuses,
                     const QString& current) {
    if (order.isEmpty())
        return QString();
    QString chosen;
    for (const QString& cand : order)
        if (statuses.value(cand) == QStringLiteral("Playing")) { chosen = cand; break; }
    if (chosen.isEmpty())
        chosen = order.contains(current) ? current : order.first();
    return chosen;
}

TrackState resolveTrack(const QVariantMap& props, const QString& service) {
    TrackState s;
    s.status = props.value(QStringLiteral("PlaybackStatus")).toString();

    const QVariantMap meta = qdbus_cast<QVariantMap>(props.value(QStringLiteral("Metadata")));
    s.title = meta.value(QStringLiteral("xesam:title")).toString();

    // xesam:artist is "as" in the spec and arrives as a QDBusArgument, which
    // qdbus_cast demarshals. A few players send a bare string instead — that
    // ALSO works, but via qdbus_cast's own fall-through to QVariant's
    // QString->QStringList conversion, NOT via the toStringList() line below.
    //
    // That line is vestigial, and measured to be so (2026-07-17): it only runs
    // when the cast yields an empty list, which happens solely for an absent
    // key, an empty list, or a wrong-typed value — and toStringList() yields
    // empty for all three, so it cannot change the result. It is kept only
    // because it is harmless and removing it is a behaviour change nobody has a
    // reason to risk on an exotic QDBusArgument shape. Do not mistake it for the
    // thing that handles the bare-string case; tst_mpris_state.cpp's
    // artistFromBareString pins the real mechanism.
    QStringList artists = qdbus_cast<QStringList>(meta.value(QStringLiteral("xesam:artist")));
    if (artists.isEmpty())
        artists = meta.value(QStringLiteral("xesam:artist")).toStringList();
    s.artist = artists.join(QStringLiteral(", "));

    s.album = meta.value(QStringLiteral("xesam:album")).toString();
    s.artUrl = meta.value(QStringLiteral("mpris:artUrl")).toString();
    // Some players (e.g. Chromium) advertise a file:// art path that may be
    // stale/unreadable. Validate local files so QML never tries a bad URL
    // (which would emit an Image "Cannot open" warning); http(s) is passed through.
    if (s.artUrl.startsWith(QStringLiteral("file://"))) {
        const QString local = QUrl(s.artUrl).toLocalFile();
        if (local.isEmpty() || !QFileInfo(local).isReadable())
            s.artUrl.clear();
    }
    s.lengthUs = meta.value(QStringLiteral("mpris:length")).toLongLong();
    s.playerName = playerNameFromService(service);

    // A service can be registered on the bus (CanControl: true) with no track
    // actually loaded — e.g. a browser tab with audio capability but nothing
    // played yet, or a player that was just stopped. Treat that as genuinely
    // "nothing playing" rather than showing a blank card: require either a real
    // title or an active Playing/Paused status.
    const bool hasTrack = !s.title.isEmpty();
    const bool isActive = s.status == QStringLiteral("Playing") ||
                          s.status == QStringLiteral("Paused");
    s.available = hasTrack || isActive;
    if (!s.available) {
        s.title = s.artist = s.album = s.artUrl = QString();
        s.lengthUs = 0;
    }
    return s;
}

bool visiblyDiffers(const TrackState& a, const TrackState& b) {
    return a.available != b.available || a.status != b.status || a.title != b.title ||
           a.artist != b.artist || a.album != b.album || a.artUrl != b.artUrl ||
           a.playerName != b.playerName;
}

}  // namespace mpris
