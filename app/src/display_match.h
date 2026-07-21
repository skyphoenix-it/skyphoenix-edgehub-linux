#pragma once

#include <QJsonObject>
#include <QString>
#include <Qt>

// Boot-time window placement policy. A positive match always wins. When no
// display identity has ever been configured, the primary screen remains the
// first-run fallback. Once the user has selected a target, a failed match must
// keep the Hub hidden instead of silently taking over the primary screen. The
// sole exception is an explicit --reset-wizard request, which gets a dedicated
// windowed recovery placement.
enum class StartupDisplayPlacement {
    MatchedTarget,
    PrimaryFallback,
    PrimaryRecovery,
    KeepHidden,
};

// Whether any persistent display identity field is configured. Empty strings
// are treated like an absent field; non-empty malformed/manual values are still
// explicit configuration and therefore fail safe (KeepHidden) when unmatched.
bool hasConfiguredTargetIdentity(const QString& edidHash, const QString& model,
                                 const QString& connector);

// Pure startup-policy seam used by main.cpp after strict screen matching.
StartupDisplayPlacement decideStartupDisplayPlacement(bool hasConfiguredTarget,
                                                       bool targetMatched,
                                                       bool recoveryRequested);

// Live target-removal policy. Hiding is a non-negotiable safety invariant: a
// compositor may otherwise relocate a fullscreen window from the removed panel
// onto primary. Notification and selection guidance are independent signals.
struct TargetRemovalSafetyDecision {
    bool hideWindow = false;
    bool notify = false;
    bool requestSelection = false;
};

TargetRemovalSafetyDecision decideTargetRemovalSafety(bool wasTarget,
                                                       const QString& fallbackBehavior,
                                                       bool notifyDisconnect);

// Human-facing desktop notification content for a lost target display.  Kept
// pure so wording and the selection-guidance branch are testable without a
// notification daemon or a live desktop session.
struct DisplayDisconnectNotice {
    QString summary;
    QString body;
};

DisplayDisconnectNotice displayDisconnectNotice(const QString& screenName,
                                                 bool requestSelection);

// Compute the stable identity hash for a display from its four identity fields
// (connector name + model + manufacturer + serial). The hub uses this both to
// serialize a screen's `edidHash` and to match the configured target screen, so
// the two paths MUST agree — hence a single shared implementation.
QString screenIdentityHash(const QString& name, const QString& model,
                           const QString& manufacturer, const QString& serial);

// Canonical orientation spelling (hyphenated), shared by the initial screens
// payload and the live sensor push so QML never sees two spellings. Returns an
// empty string for Qt::PrimaryOrientation / unknown values.
QString orientationName(Qt::ScreenOrientation o);

// Parse a metrics-JSON byte buffer into a QJsonObject. Returns an empty object on a
// malformed/empty buffer (warning once, via an atomic guard shared across threads).
// Extracted as a testable seam so the malformed-input branch can be exercised without
// a real collector (which always yields valid JSON on a normal host).
QJsonObject parseMetrics(const QByteArray& metricsJson);

// Collect system metrics from the Rust core and parse them into a QJsonObject.
// Returns an empty object on collection/parse failure (warns once).
QJsonObject metricsToJson();
