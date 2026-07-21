// Decision table for reconcileOnPull() - the reconnect PULL-before-PUSH state
// machine. Pure, GUILESS.
#include <QtTest>

#include "reconcile.h"

// Refuse to run outside a sandbox: this test would otherwise clobber the
// developer's real config / running hub. See hermetic.h.
#include "hermetic.h"
XENEON_REQUIRE_HERMETIC_ENV();

Q_DECLARE_METATYPE(ReconcileAction)

class TstReconcile : public QObject {
    Q_OBJECT
private slots:
    void table_data() {
        QTest::addColumn<bool>("awaitingHub");
        QTest::addColumn<bool>("havePendingPush");
        QTest::addColumn<QString>("pulled");
        QTest::addColumn<QString>("lastHub");
        QTest::addColumn<bool>("suppressed");
        QTest::addColumn<ReconcileAction>("expect");

        // ── Not reconciling a reconnect: plain adopt vs suppress ──
        QTest::newRow("adopt-normal")
            << false << false << QString("A") << QString("B") << false << ReconcileAction::AdoptHub;
        QTest::newRow("adopt-suppressed")
            << false << false << QString("A") << QString("B") << true  << ReconcileAction::Ignore;
        QTest::newRow("adopt-normal-with-pending-not-awaiting")
            << false << true  << QString("A") << QString("B") << false << ReconcileAction::AdoptHub;

        // ── Reconnect reconcile: hub CHANGED while offline → drop our stale edit ──
        QTest::newRow("hub-changed-drop")
            << true  << true  << QString("NEW") << QString("OLD") << false << ReconcileAction::DropEdit;
        // hubChanged wins even if suppressed.
        QTest::newRow("hub-changed-drop-suppressed")
            << true  << true  << QString("NEW") << QString("OLD") << true  << ReconcileAction::DropEdit;
        // hubChanged with NO buffered edit still drops (adopts the newer hub state).
        QTest::newRow("hub-changed-no-pending-drop")
            << true  << false << QString("NEW") << QString("OLD") << false << ReconcileAction::DropEdit;

        // ── Reconnect reconcile: hub UNCHANGED → (re)push our buffered edit ──
        QTest::newRow("hub-same-keep")
            << true  << true  << QString("SAME") << QString("SAME") << false << ReconcileAction::KeepAndPushEdit;
        // KeepAndPushEdit wins over the suppression window (hubChanged=false, pending).
        QTest::newRow("hub-same-keep-suppressed")
            << true  << true  << QString("SAME") << QString("SAME") << true  << ReconcileAction::KeepAndPushEdit;
        // Empty pull is treated as "unchanged" → keep the edit, don't drop it.
        QTest::newRow("empty-pull-keep")
            << true  << true  << QString("")     << QString("OLD")  << false << ReconcileAction::KeepAndPushEdit;

        // ── Empty baseline (no prior successful pull) + NON-EMPTY pull → adopt the
        //    hub (DropEdit): we can't prove our buffered edit is newer than what's on
        //    the device, so don't clobber a possible device-side edit. ──
        QTest::newRow("empty-baseline-nonempty-pull-adopt")
            << true  << true  << QString("DEVICE") << QString("")   << false << ReconcileAction::DropEdit;

        // ── Reconnect but nothing buffered → falls through to adopt/suppress ──
        QTest::newRow("awaiting-no-pending-adopt")
            << true  << false << QString("SAME") << QString("SAME") << false << ReconcileAction::AdoptHub;
        QTest::newRow("awaiting-no-pending-suppressed")
            << true  << false << QString("SAME") << QString("SAME") << true  << ReconcileAction::Ignore;
    }
    void table() {
        QFETCH(bool, awaitingHub);
        QFETCH(bool, havePendingPush);
        QFETCH(QString, pulled);
        QFETCH(QString, lastHub);
        QFETCH(bool, suppressed);
        QFETCH(ReconcileAction, expect);
        QCOMPARE(reconcileOnPull(awaitingHub, havePendingPush, pulled, lastHub, suppressed), expect);
    }
};

QTEST_GUILESS_MAIN(TstReconcile)
#include "tst_reconcile.moc"
