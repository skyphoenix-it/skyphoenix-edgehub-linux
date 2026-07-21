#pragma once

#include <QSize>
#include <QString>
#include <QVector>

struct ManagerScreenIdentity {
    QString model;
    QString manufacturer;
    QSize size;
};

inline bool managerScreenIsEdge(const ManagerScreenIdentity& screen) {
    if (screen.model.contains(QStringLiteral("XENEON"), Qt::CaseInsensitive)
        || screen.manufacturer.contains(QStringLiteral("Corsair"), Qt::CaseInsensitive))
        return true;
    return screen.size == QSize(2560, 720) || screen.size == QSize(720, 2560);
}

// Return a safe screen index, preferring the primary screen. A negative result
// is a hard stop: the Manager must remain hidden when every output is the Edge.
inline int managerSafeScreenIndex(const QVector<ManagerScreenIdentity>& screens,
                                  int primaryIndex) {
    if (primaryIndex >= 0 && primaryIndex < screens.size()
        && !managerScreenIsEdge(screens.at(primaryIndex)))
        return primaryIndex;

    for (int i = 0; i < screens.size(); ++i)
        if (!managerScreenIsEdge(screens.at(i))) return i;
    return -1;
}
