#include "autostart.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QStandardPaths>
#include <QFile>
#include <QLatin1Char>
#include <QString>
#include <QTextStream>

QString quoteExecForDesktop(const QString& execPath) {
    // Quote the Exec path if it contains spaces (an install dir with a space would
    // otherwise produce a broken Exec line per the .desktop spec).
    if (execPath.contains(QLatin1Char(' ')))
        return QLatin1Char('"') + execPath + QLatin1Char('"');
    return execPath;
}

bool applyAutostart(bool enabled) {
    // QStandardPaths, NOT QDir::homePath(): homePath ignores XDG_CONFIG_HOME, so
    // a sandboxed test hub (isolated XDG_CONFIG_HOME, real HOME) wrote its
    // autostart entry into the REAL ~/.config/autostart - with Exec pointing at a
    // throwaway worktree build - and a later cleanup deleted the user's genuine
    // entry alongside it. ConfigLocation honours the env, so isolation actually
    // isolates.
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/autostart";
    const QString path = dir + "/xeneon-edge-hub.desktop";
    if (!enabled) {
        // Removing a non-existent entry is already "off" (success); otherwise
        // report whether the removal actually succeeded rather than lying true.
        if (!QFile::exists(path))
            return true;
        return QFile::remove(path);
    }
    if (!QDir().mkpath(dir))
        return false;
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "Could not write autostart entry:" << path;
        return false;
    }
    const QString execPath = quoteExecForDesktop(QCoreApplication::applicationFilePath());
    QTextStream ts(&f);
    ts << "[Desktop Entry]\n"
       << "Type=Application\n"
       << "Name=Xeneon Edge Linux Hub\n"
       << "Comment=Native Linux widget platform for secondary touchscreen displays\n"
       << "Exec=" << execPath << "\n"
       << "Icon=xeneon-edge-hub\n"
       << "Categories=Utility;\n"
       << "Terminal=false\n"
       << "X-GNOME-Autostart-enabled=true\n";
    f.close();
    qInfo() << "Autostart entry written:" << path;
    return true;
}
