#pragma once

#include <QJsonObject>
#include <QString>
#include <Qt>

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
