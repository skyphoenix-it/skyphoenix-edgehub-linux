#pragma once

#include <QDir>
#include <QFileInfo>
#include <QString>

#include <optional>

// Resolve a user-supplied image `name` to a safe absolute path INSIDE `imagesDir`,
// or std::nullopt if it would escape the directory (or is empty / "." / "..").
//
// A crafted name (e.g. "../../.config/foo", an absolute path, or "a/b") is first
// collapsed to its bare filename, then the resolved path is verified to still lie
// within the images directory before it is returned - so callers can delete/open
// it without traversing outside.
inline std::optional<QString> sanitizeImageName(const QString& name,
                                                const QString& imagesDir) {
    const QString base = QFileInfo(name).fileName();
    if (base.isEmpty() || base == QLatin1String(".") || base == QLatin1String(".."))
        return std::nullopt;
    const QString dirPath = QDir::cleanPath(QDir(imagesDir).absolutePath());
    const QString target = QDir::cleanPath(dirPath + QLatin1Char('/') + base);
    // Defense in depth. `base` is already a bare leaf (fileName() above strips
    // every directory component and we reject ""/"."/".."), so `target` ALWAYS
    // lies inside `dirPath` and this branch cannot be reached through the public
    // function - tst_path_sanitize.cpp throws ../, absolute paths and deep
    // traversals at it and every one is contained, never rejected here. It is
    // kept, and GCOVR-excluded rather than faked with an unreachable test,
    // BECAUSE it must survive `fileName()` normalization ever being weakened: if
    // that changes, this becomes the primary escape guard and the exclusion
    // marker is the signal to add a real reject test then.
    if (target != dirPath && !target.startsWith(dirPath + QLatin1Char('/')))
        return std::nullopt;  // GCOVR_EXCL_LINE
    return target;
}
