#include "display_match.h"

#include <QByteArray>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonParseError>

#include <atomic>
#include <cstdint>

#include "xeneon_core.h"
#include "xeneon_string.h"

bool hasConfiguredTargetIdentity(const QString& edidHash, const QString& model,
                                 const QString& connector) {
    return !edidHash.isEmpty() || !model.isEmpty() || !connector.isEmpty();
}

StartupDisplayPlacement decideStartupDisplayPlacement(bool hasConfiguredTarget,
                                                       bool targetMatched,
                                                       bool recoveryRequested) {
    if (targetMatched)
        return StartupDisplayPlacement::MatchedTarget;
    if (hasConfiguredTarget && recoveryRequested)
        return StartupDisplayPlacement::PrimaryRecovery;
    if (hasConfiguredTarget)
        return StartupDisplayPlacement::KeepHidden;
    return StartupDisplayPlacement::PrimaryFallback;
}

TargetRemovalSafetyDecision decideTargetRemovalSafety(bool wasTarget,
                                                       const QString& fallbackBehavior,
                                                       bool notifyDisconnect) {
    TargetRemovalSafetyDecision decision;
    if (!wasTarget)
        return decision;

    // Independent of user-facing fallback preferences, a removed target can no
    // longer safely own a visible window. Hiding prevents compositor relocation
    // onto primary for hide, notify, ask, and malformed/manual policy values.
    decision.hideWindow = true;
    decision.requestSelection = fallbackBehavior == QLatin1String("ask");
    decision.notify = notifyDisconnect
                      || fallbackBehavior == QLatin1String("notify")
                      || decision.requestSelection;
    return decision;
}

DisplayDisconnectNotice displayDisconnectNotice(const QString& screenName,
                                                 bool requestSelection) {
    const QString display = screenName.trimmed().isEmpty()
                                ? QStringLiteral("The dashboard display")
                                : QStringLiteral("Dashboard display %1").arg(screenName.trimmed());
    DisplayDisconnectNotice notice;
    notice.summary = QStringLiteral("Dashboard display disconnected");
    if (requestSelection) {
        notice.body = QStringLiteral(
            "%1 is unavailable. The dashboard is hidden for safety. Open Xeneon "
            "Edge Manager to select a display.").arg(display);
    } else {
        notice.body = QStringLiteral(
            "%1 is unavailable. The dashboard is hidden and waiting for reconnection.")
                          .arg(display);
    }
    return notice;
}

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
