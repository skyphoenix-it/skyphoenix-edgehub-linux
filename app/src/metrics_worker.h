#pragma once

#include <QByteArray>
#include <QJsonDocument>
#include <QObject>
#include <QTimer>

#include "display_match.h"

// MetricsWorker — runs the (potentially slow) Rust metrics collection + JSON
// serialization on a dedicated thread so the 2s poll never blocks/janks the GUI
// event loop. It emits the compact JSON to the GUI thread, which pushes it onto
// the QML roots. begin()/stop() run ON the worker thread (invoked via the thread's
// event loop), so the QTimer lives and fires there.
class MetricsWorker : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE void begin() {
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, &MetricsWorker::poll);
        m_timer->start(2000);
        poll();   // emit an initial sample immediately
    }
    Q_INVOKABLE void stop() {
        if (m_timer) { m_timer->stop(); delete m_timer; m_timer = nullptr; }
    }
signals:
    void metricsReady(const QByteArray& json);
private:
    void poll() { emit metricsReady(QJsonDocument(metricsToJson()).toJson(QJsonDocument::Compact)); }
    QTimer* m_timer = nullptr;
};
