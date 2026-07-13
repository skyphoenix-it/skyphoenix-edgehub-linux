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
// within the images directory before it is returned — so callers can delete/open
// it without traversing outside.
inline std::optional<QString> sanitizeImageName(const QString& name,
                                                const QString& imagesDir) {
    const QString base = QFileInfo(name).fileName();
    if (base.isEmpty() || base == QLatin1String(".") || base == QLatin1String(".."))
        return std::nullopt;
    const QString dirPath = QDir::cleanPath(QDir(imagesDir).absolutePath());
    const QString target = QDir::cleanPath(dirPath + QLatin1Char('/') + base);
    if (target != dirPath && !target.startsWith(dirPath + QLatin1Char('/')))
        return std::nullopt;
    return target;
}
