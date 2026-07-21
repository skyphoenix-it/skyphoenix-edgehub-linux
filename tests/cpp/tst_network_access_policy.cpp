#include <QtTest>

#include "hermetic.h"
#include "network_access_policy.h"

XENEON_REQUIRE_HERMETIC_ENV();

class NetworkAccessPolicyTest final : public QObject {
    Q_OBJECT

private slots:
    void qmlNetworkManagerAllowsSameOriginRedirectsOnly() {
        QObject owner;
        XeneonNetworkAccessManagerFactory factory;
        QNetworkAccessManager* manager = factory.create(&owner);

        QVERIFY(manager != nullptr);
        QCOMPARE(manager->parent(), &owner);
        QCOMPARE(manager->redirectPolicy(), QNetworkRequest::SameOriginRedirectPolicy);
    }
};

QTEST_MAIN(NetworkAccessPolicyTest)
#include "tst_network_access_policy.moc"
