#pragma once

#include <QObject>
#include <QString>

class QSocketNotifier;

// OrientationSensor — reads the Corsair Xeneon Edge's orientation from its vendor
// HID pipe (/dev/hidrawN, vendor 1b1c product 1d0d). The Edge pushes an unsolicited
// 64-byte report whenever the panel is rotated; byte 7 carries the orientation:
//   0x03 = portrait (upright)   0x00 = +90° CW    0x01 = 180°   0x02 = -90° CW
// which we map to the content rotation (degrees, clockwise) that keeps the UI
// upright. Requires read access to the hidraw node (see the 99-xeneon-edge udev
// rule); if the node is missing or unreadable the sensor simply stays inactive.
class OrientationSensor : public QObject {
    Q_OBJECT
public:
    explicit OrientationSensor(QObject* parent = nullptr);
    ~OrientationSensor() override;

    // Locate + open the Edge hidraw node and begin watching it. Returns true if
    // the device was opened and is being read.
    bool start();
    bool active() const { return m_fd >= 0; }

    // Current content rotation (0/90/180/270), or -1 if unknown/no reading yet.
    int rotation() const { return m_rotation; }

signals:
    void rotationChanged(int rotation);

private slots:
    void onReadable();

private:
    // Disable the notifier + close the fd (on a fatal read error / device unplug),
    // so QSocketNotifier stops re-firing on a hung-up fd (which would busy-loop).
    void stopWatching();
    // Scan /sys/class/hidraw for the Edge; returns "/dev/hidrawN" or empty.
    static QString findEdgeHidraw();
    // Map an orientation byte (report[7]) to a content rotation, or -1 if unknown.
    static int byteToRotation(unsigned char b);

    int m_fd = -1;
    int m_rotation = -1;
    QSocketNotifier* m_notifier = nullptr;
};
