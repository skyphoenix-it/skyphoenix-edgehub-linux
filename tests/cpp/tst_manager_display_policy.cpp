#include <QtTest>

#include "manager_display_policy.h"

class TstManagerDisplayPolicy : public QObject {
    Q_OBJECT
private slots:
    void identifiesEdgeByModelManufacturerAndSize() {
        QVERIFY(managerScreenIsEdge({QStringLiteral("XENEON EDGE"), {}, QSize(100, 100)}));
        QVERIFY(managerScreenIsEdge({{}, QStringLiteral("Corsair"), QSize(100, 100)}));
        QVERIFY(managerScreenIsEdge({{}, {}, QSize(2560, 720)}));
        QVERIFY(managerScreenIsEdge({{}, {}, QSize(720, 2560)}));
        QVERIFY(!managerScreenIsEdge({QStringLiteral("Desktop"),
                                      QStringLiteral("Acme"), QSize(1920, 1080)}));
    }

    void refusesEdgeOnlyConfiguration() {
        const QVector<ManagerScreenIdentity> screens = {
            {QStringLiteral("XENEON EDGE"), QStringLiteral("Corsair"), QSize(720, 2560)}
        };
        QCOMPARE(managerSafeScreenIndex(screens, 0), -1);
    }

    void prefersSafePrimaryThenFirstSafeFallback() {
        const ManagerScreenIdentity edge = {
            QStringLiteral("XENEON EDGE"), QStringLiteral("Corsair"), QSize(720, 2560)
        };
        const ManagerScreenIdentity desktopA = {
            QStringLiteral("Desktop A"), QStringLiteral("Acme"), QSize(1920, 1080)
        };
        const ManagerScreenIdentity desktopB = {
            QStringLiteral("Desktop B"), QStringLiteral("Acme"), QSize(2560, 1440)
        };
        QCOMPARE(managerSafeScreenIndex({edge, desktopA, desktopB}, 2), 2);
        QCOMPARE(managerSafeScreenIndex({edge, desktopA, desktopB}, 0), 1);
    }
};

QTEST_GUILESS_MAIN(TstManagerDisplayPolicy)
#include "tst_manager_display_policy.moc"
