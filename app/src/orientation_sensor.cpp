#include "orientation_sensor.h"

#include <QSocketNotifier>
#include <QDir>
#include <QFile>
#include <QDebug>

#include <fcntl.h>
#include <unistd.h>
#include <cerrno>

OrientationSensor::OrientationSensor(QObject* parent) : QObject(parent) {}

OrientationSensor::~OrientationSensor() {
    if (m_notifier) {
        m_notifier->setEnabled(false);
        delete m_notifier;
    }
    if (m_fd >= 0)
        ::close(m_fd);
}

QString OrientationSensor::findEdgeHidraw() {
    // The kernel exposes each hidraw as /sys/class/hidraw/hidrawN with a
    // device/uevent carrying HID_ID=BUS:VVVVVVVV:PPPPPPPP. Match Corsair 1b1c /
    // Xeneon Edge 1d0d (hex, uppercase in uevent).
    QDir dir(QStringLiteral("/sys/class/hidraw"));
    const auto entries = dir.entryList(QStringList{QStringLiteral("hidraw*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString& name : entries) {
        QFile uevent(QStringLiteral("/sys/class/hidraw/") + name + QStringLiteral("/device/uevent"));
        if (!uevent.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        const QString text = QString::fromUtf8(uevent.readAll());
        // e.g. HID_ID=0003:00001B1C:00001D0D
        if (text.contains(QStringLiteral("1B1C"), Qt::CaseInsensitive)
            && text.contains(QStringLiteral("1D0D"), Qt::CaseInsensitive)) {
            return QStringLiteral("/dev/") + name;
        }
    }
    return QString();
}

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

bool OrientationSensor::start() {
    const QString path = findEdgeHidraw();
    if (path.isEmpty()) {
        qInfo() << "OrientationSensor: no Xeneon Edge hidraw node found (auto-rotate disabled)";
        return false;
    }
    m_fd = ::open(path.toUtf8().constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (m_fd < 0) {
        qWarning() << "OrientationSensor: cannot open" << path << "-" << strerror(errno)
                   << "(install the 99-xeneon-edge udev rule to grant access; auto-rotate disabled)";
        return false;
    }
    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &OrientationSensor::onReadable);
    qInfo() << "OrientationSensor: watching" << path << "for Xeneon Edge orientation";
    // Drain any immediately-available report so we start with the real state.
    onReadable();
    return true;
}

void OrientationSensor::onReadable() {
    unsigned char buf[64];
    // Consume all pending reports; keep the last valid orientation.
    while (true) {
        const ssize_t n = ::read(m_fd, buf, sizeof(buf));
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                break;
            if (errno == EINTR)
                continue;
            qWarning() << "OrientationSensor: read error" << strerror(errno);
            break;
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
