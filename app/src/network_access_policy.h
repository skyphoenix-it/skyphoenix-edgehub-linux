#pragma once

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QQmlNetworkAccessManagerFactory>

// QML XMLHttpRequest and Image share the engine's QNetworkAccessManager. Keep
// redirects on the original origin so a URL that passed NetHub's host allowlist
// cannot silently bounce to a different host after the policy decision. Direct
// remote Image sources are separately rejected at their input boundaries.
class XeneonNetworkAccessManagerFactory final : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager* create(QObject* parent) override {
        auto* manager = new QNetworkAccessManager(parent);
        manager->setRedirectPolicy(QNetworkRequest::SameOriginRedirectPolicy);
        return manager;
    }
};
