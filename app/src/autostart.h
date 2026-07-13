#pragma once

#include <QString>

// Quote an Exec program path per the freedesktop .desktop spec: paths containing a
// space must be wrapped in double quotes, otherwise the Exec line parses as multiple
// arguments. Returned unchanged when there is no space. Extracted as a testable seam.
QString quoteExecForDesktop(const QString& execPath);

// Install/remove the hub's XDG autostart .desktop entry
// (~/.config/autostart/xeneon-edge-hub.desktop) pointing at the current binary,
// so "start on login" actually takes effect.
//
// Returns true on success. When disabling, returns the real QFile::remove result
// (or true if the entry didn't exist) rather than optimistically claiming success.
bool applyAutostart(bool enabled);
