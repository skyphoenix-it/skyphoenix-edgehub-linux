// Orientation byte → content rotation mapping (calibrated on-device). Pure static
// function, no hardware. GUILESS.
#include <QtTest>

#include "orientation_sensor.h"

class TstOrientationByte : public QObject {
    Q_OBJECT
private slots:
    void mapping_data() {
        QTest::addColumn<int>("byte");
        QTest::addColumn<int>("rotation");
        QTest::newRow("0x03-upright")   << 0x03 << 0;
        QTest::newRow("0x00-plus90")    << 0x00 << 270;
        QTest::newRow("0x01-inverted")  << 0x01 << 180;
        QTest::newRow("0x02-minus90")   << 0x02 << 90;
        QTest::newRow("0x04-unknown")   << 0x04 << -1;
        QTest::newRow("0xFF-unknown")   << 0xFF << -1;
        QTest::newRow("0x10-unknown")   << 0x10 << -1;
    }
    void mapping() {
        QFETCH(int, byte);
        QFETCH(int, rotation);
        QCOMPARE(OrientationSensor::byteToRotation(static_cast<unsigned char>(byte)), rotation);
    }
};

QTEST_GUILESS_MAIN(TstOrientationByte)
#include "tst_orientation_byte.moc"
