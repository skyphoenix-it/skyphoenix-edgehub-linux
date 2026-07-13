#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

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

    // Map an orientation byte (report[7]) to a content rotation, or -1 if unknown.
    //   0x03→0, 0x00→270, 0x01→180, 0x02→90, else→-1
    // Public + static so it can be unit-tested without opening a hidraw node.
    static int byteToRotation(unsigned char b);

    // ── Test seams (no hardware) ──
    // Open + watch an arbitrary path (e.g. a FIFO) as if it were the Edge hidraw
    // node, so the read/EOF/error → retry-timer path can be exercised headlessly.
    bool openForTest(const QString& path) { return openAndWatch(path); }
    // Whether the reopen retry timer is currently armed (device-lost recovery).
    bool retryActiveForTest() const { return m_retry.isActive(); }

signals:
    void rotationChanged(int rotation);

private slots:
    void onReadable();
    // Poll for the device coming back after an unplug and re-open it transparently.
    void tryReopen();

private:
    // Open the hidraw node, wire up the notifier, and seed the initial orientation.
    bool openAndWatch(const QString& path);
    // Disable the notifier + close the fd (on a fatal read error / device unplug),
    // so QSocketNotifier stops re-firing on a hung-up fd (which would busy-loop).
    void stopWatching();
    // stopWatching() + arm the reopen timer, for the device-lost (unplug) case.
    void handleDeviceLost();
    // Actively query the current orientation once at open time (the panel only
    // pushes reports on *change*, so without this the UI can start mis-rotated).
    void queryInitialOrientation();
    // Scan /sys/class/hidraw for the Edge; returns "/dev/hidrawN" or empty.
    static QString findEdgeHidraw();

    int m_fd = -1;
    int m_rotation = -1;
    QSocketNotifier* m_notifier = nullptr;
    QTimer m_retry;   // polls for the hidraw node to reappear after an unplug
};
