#pragma once

#include <QString>

#include "xeneon_core.h"

// RAII wrapper around a heap `char*` handed back by the Rust core. Frees it via
// xeneon_string_free() on destruction so FFI string returns can't leak. Shared by
// the hub's bridges/helpers (the Manager keeps its own trimmed copy).
class XeneonString {
    char* ptr;
public:
    explicit XeneonString(char* p) : ptr(p) {}
    ~XeneonString() { if (ptr) xeneon_string_free(ptr); }
    XeneonString(const XeneonString&) = delete;
    XeneonString& operator=(const XeneonString&) = delete;
    const char* c_str() const { return ptr; }
    QString qstring() const { return ptr ? QString::fromUtf8(ptr) : QString(); }
    bool isNull() const { return ptr == nullptr; }
    operator bool() const { return ptr != nullptr; }
};
