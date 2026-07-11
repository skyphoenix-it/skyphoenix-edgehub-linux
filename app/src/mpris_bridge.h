#ifndef MPRIS_BRIDGE_H
#define MPRIS_BRIDGE_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantMap>
#include <QtDBus/QDBusConnection>

// MprisBridge — exposes the active MPRIS media player (Spotify, browsers /
// YouTube Music, etc.) to QML: now-playing metadata + transport control.
//
// It discovers `org.mpris.MediaPlayer2.*` services on the session bus, prefers
// whichever is Playing, watches PropertiesChanged for live updates, and polls
// Position while playing. Exposed as the `media` context property.
class MprisBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString artist READ artist NOTIFY changed)
    Q_PROPERTY(QString album READ album NOTIFY changed)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)          // Playing/Paused/Stopped
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(QString playerName READ playerName NOTIFY changed)
    Q_PROPERTY(double position READ position NOTIFY positionChanged) // 0..1 fraction

public:
    explicit MprisBridge(QObject* parent = nullptr);

    bool available() const { return m_available; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString album() const { return m_album; }
    QString artUrl() const { return m_artUrl; }
    QString status() const { return m_status; }
    bool playing() const { return m_status == QStringLiteral("Playing"); }
    QString playerName() const { return m_playerName; }
    double position() const {
        return m_lengthUs > 0 ? double(m_positionUs) / double(m_lengthUs) : 0.0;
    }

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

signals:
    void changed();
    void positionChanged();

private slots:
    void onPropertiesChanged(const QString& iface, const QVariantMap& changed,
                             const QStringList& invalidated);
    void reevaluate();  // (re)pick the active player
    void poll();        // refresh Position while playing

private:
    QStringList mprisServices() const;
    QString statusOf(const QString& service) const;
    void connectTo(const QString& service);
    void refresh();
    void callPlayer(const char* method);

    QDBusConnection m_bus;
    QString m_service, m_playerName, m_title, m_artist, m_album, m_artUrl, m_status;
    qlonglong m_lengthUs = 0;
    qlonglong m_positionUs = 0;
    bool m_available = false;
    QTimer m_poll;
    QTimer m_rescan;
};

#endif // MPRIS_BRIDGE_H
