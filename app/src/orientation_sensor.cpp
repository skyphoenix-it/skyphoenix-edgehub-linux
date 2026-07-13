#include "orientation_sensor.h"

#include <QSocketNotifier>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QDebug>

#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <sys/ioctl.h>
#include <linux/hidraw.h>

OrientationSensor::OrientationSensor(QObject* parent) : QObject(parent) {
    // Poll timer used only after an unplug, to re-open the node when it returns.
    m_retry.setInterval(3000);
    connect(&m_retry, &QTimer::timeout, this, &OrientationSensor::tryReopen);
}

// GCOVR_EXCL_START (dtor teardown of a live hidraw fd/notifier; the FIFO test tears
// down via EOF before destruction, so these hardware-cleanup branches aren't taken).
OrientationSensor::~OrientationSensor() {
    if (m_notifier) {
        m_notifier->setEnabled(false);
        delete m_notifier;
    }
    if (m_fd >= 0)
        ::close(m_fd);
}
// GCOVR_EXCL_STOP

// GCOVR_EXCL_START (hardware: scans /sys/class/hidraw for the Corsair Xeneon Edge —
// no such device in headless CI; the open/read/EOF path is tested via a FIFO seam).
QString OrientationSensor::findEdgeHidraw() {
    // The kernel exposes each hidraw as /sys/class/hidraw/hidrawN with a
    // device/uevent carrying HID_ID=BUS:VVVVVVVV:PPPPPPPP. Match Corsair 1b1c /
    // Xeneon Edge 1d0d (hex, uppercase in uevent).
    // Match the exact HID_ID vendor:product field (e.g. HID_ID=0003:00001B1C:00001D0D)
    // rather than loose substrings anywhere in the uevent: two independent
    // "contains" checks could both hit on an unrelated device whose numbers merely
    // happen to include 1B1C and 1D0D somewhere, or on a Corsair device with a
    // different product id. Anchoring on HID_ID=<bus>:<vid>:<pid> ties them together.
    static const QRegularExpression hidIdRe(
        QStringLiteral("HID_ID=[0-9A-F]+:0*1B1C:0*1D0D"),
        QRegularExpression::CaseInsensitiveOption);
    QDir dir(QStringLiteral("/sys/class/hidraw"));
    const auto entries = dir.entryList(QStringList{QStringLiteral("hidraw*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString& name : entries) {
        QFile uevent(QStringLiteral("/sys/class/hidraw/") + name + QStringLiteral("/device/uevent"));
        if (!uevent.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        const QString text = QString::fromUtf8(uevent.readAll());
        if (hidIdRe.match(text).hasMatch())
            return QStringLiteral("/dev/") + name;
    }
    return QString();
}
// GCOVR_EXCL_STOP

int OrientationSensor::byteToRotation(unsigned char b) {
    // Content rotation (clockwise degrees) that keeps the UI upright for each
    // physical orientation the Edge reports. Calibrated ON-DEVICE:
    //   0x03 upright portrait → 0°, 0x01 inverted portrait → 180° (both verified
    //   upright); the two landscapes needed swapping (they came out inverted at
    //   90/270): 0x00 (+90°CW) → 270°, 0x02 (-90°CW) → 90°.
    switch (b) {
    case 0x03: return 0;
    case 0x00: return 270;
    case 0x01: return 180;
    case 0x02: return 90;
    default:   return -1;
    }
}

// GCOVR_EXCL_START (production entry: locates the real hidraw node via findEdgeHidraw;
// tests drive openAndWatch() directly through the openForTest FIFO seam instead).
bool OrientationSensor::start() {
    const QString path = findEdgeHidraw();
    if (path.isEmpty()) {
        qInfo() << "OrientationSensor: no Xeneon Edge hidraw node found (auto-rotate disabled)";
        return false;
    }
    return openAndWatch(path);
}
// GCOVR_EXCL_STOP

bool OrientationSensor::openAndWatch(const QString& path) {
    m_fd = ::open(path.toUtf8().constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (m_fd < 0) {
        qWarning() << "OrientationSensor: cannot open" << path << "-" << strerror(errno)
                   << "(install the 99-xeneon-edge udev rule to grant access; auto-rotate disabled)";
        return false;
    }
    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &OrientationSensor::onReadable);
    qInfo() << "OrientationSensor: watching" << path << "for Xeneon Edge orientation";
    // The panel only pushes a report when the orientation *changes*, so actively
    // query the current state once — otherwise the UI stays at its default until
    // the user physically rotates the panel.
    queryInitialOrientation();
    // Also drain any immediately-available change report.
    onReadable();
    return true;
}

void OrientationSensor::queryInitialOrientation() {
    if (m_fd < 0)
        return;
    // HID GET_REPORT for input report id 0x01 — the same report the panel pushes
    // asynchronously on rotation. buf[0] is the report id on entry (and on return).
    unsigned char buf[64] = {0};
    buf[0] = 0x01;
    const int n = ::ioctl(m_fd, HIDIOCGINPUT(sizeof(buf)), buf);
    if (n < 8 || buf[0] != 0x01)
        return;   // unsupported / unexpected layout: fall back to the next change report
    // GCOVR_EXCL_START (HID GET_REPORT ioctl only succeeds against a real hidraw node;
    // over the FIFO test seam the ioctl fails and returns at the guard above).
    const int rot = byteToRotation(buf[7]);
    if (rot >= 0 && rot != m_rotation) {
        m_rotation = rot;
        emit rotationChanged(m_rotation);
    }
    // GCOVR_EXCL_STOP
}

void OrientationSensor::stopWatching() {
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
    if (m_fd >= 0) {
        ::close(m_fd);
        m_fd = -1;
    }
}

void OrientationSensor::handleDeviceLost() {
    stopWatching();
    // The node may reappear (device re-plugged / re-enumerated by the kernel).
    // Poll for it and re-open transparently so auto-rotate recovers without a hub
    // restart. active() reports false meanwhile (m_fd < 0).
    if (!m_retry.isActive())
        m_retry.start();
}

// GCOVR_EXCL_START (device-reappear recovery: the retry timer re-scans /sys via
// findEdgeHidraw for the panel to return — a real-hardware unplug/replug cycle).
void OrientationSensor::tryReopen() {
    if (m_fd >= 0) {   // already recovered by a prior attempt
        m_retry.stop();
        return;
    }
    const QString path = findEdgeHidraw();
    if (path.isEmpty())
        return;   // not back yet; keep polling
    if (openAndWatch(path))
        m_retry.stop();
}
// GCOVR_EXCL_STOP

void OrientationSensor::onReadable() {
    if (m_fd < 0)
        return;
    unsigned char buf[64];
    // Consume all pending reports; keep the last valid orientation.
    while (true) {
        const ssize_t n = ::read(m_fd, buf, sizeof(buf));
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                break;
            // GCOVR_EXCL_START (EINTR is a nondeterministic signal race; the -ENODEV
            // fatal path requires a real hidraw unplug — the EOF equivalent IS tested).
            if (errno == EINTR)
                continue;
            // Fatal (e.g. -ENODEV on unplug): the fd is hung up, so the notifier
            // would keep firing and spin/log-spam forever. Stop watching, then
            // poll for the device to come back.
            qWarning() << "OrientationSensor: read error" << strerror(errno)
                       << "- stopping auto-rotate (will retry if the panel returns)";
            handleDeviceLost();
            return;
            // GCOVR_EXCL_STOP
        }
        if (n == 0) {
            // EOF: the device went away. Same treatment as a fatal error.
            qWarning() << "OrientationSensor: device closed (EOF) - stopping auto-rotate"
                       << "(will retry if the panel returns)";
            handleDeviceLost();
            return;
        }
        if (n < 8)
            continue;
        // Orientation notification: report id 0x01, header byte 0x11, value at [7].
        if (buf[0] != 0x01 || buf[1] != 0x11)
            continue;
        const int rot = byteToRotation(buf[7]);
        if (rot >= 0 && rot != m_rotation) {
            m_rotation = rot;
            emit rotationChanged(m_rotation);
        }
    }
}
