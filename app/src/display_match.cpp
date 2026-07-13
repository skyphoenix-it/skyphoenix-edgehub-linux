#include "display_match.h"

#include <QByteArray>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonParseError>

#include <atomic>
#include <cstdint>

#include "xeneon_core.h"
#include "xeneon_string.h"

QString screenIdentityHash(const QString& name, const QString& model,
                           const QString& manufacturer, const QString& serial) {
    QByteArray identityData;
    identityData.append(name.toUtf8());
    identityData.append(model.toUtf8());
    identityData.append(manufacturer.toUtf8());
    identityData.append(serial.toUtf8());
    XeneonString hash(xeneon_display_compute_edid_hash(
        reinterpret_cast<const uint8_t*>(identityData.constData()),
        identityData.size()));
    return hash.qstring();
}

QString orientationName(Qt::ScreenOrientation o) {
    switch (o) {
    case Qt::LandscapeOrientation: return QStringLiteral("landscape");
    case Qt::PortraitOrientation: return QStringLiteral("portrait");
    case Qt::InvertedLandscapeOrientation: return QStringLiteral("inverted-landscape");
    case Qt::InvertedPortraitOrientation: return QStringLiteral("inverted-portrait");
    default: return QString();
    }
}

QJsonObject parseMetrics(const QByteArray& metricsJson) {
    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(metricsJson, &err);
    if (err.error != QJsonParseError::NoError) {
        // Warn once. This runs on BOTH the GUI thread (initial sample) and the
        // metrics worker thread (2s poll), so the guard must be atomic to avoid a
        // data race on a plain `bool`.
        static std::atomic<bool> warned{false};
        if (!warned.exchange(true))
            qWarning() << "parseMetrics: malformed metrics JSON:" << err.errorString();
        return QJsonObject();
    }
    return doc.object();
}

QJsonObject metricsToJson() {
    MetricsHandle* m = xeneon_metrics_collect();
    if (!m) return QJsonObject();
    XeneonString json(xeneon_metrics_to_json(m));
    xeneon_metrics_free(m);
    if (!json) return QJsonObject();
    return parseMetrics(QByteArray(json.c_str()));
}
