#include "reconcile.h"

ReconcileAction reconcileOnPull(bool awaitingHub, bool havePendingPush,
                                const QString& pulled, const QString& lastHub,
                                bool suppressed) {
    if (awaitingHub) {
        // The hub changed while we were offline only if it now reports a non-empty
        // state that differs from the last one we knew it held.
        const bool hubChanged = !pulled.isEmpty() && !lastHub.isEmpty() && pulled != lastHub;
        if (hubChanged)
            return ReconcileAction::DropEdit;
        // Empty baseline: we have NO prior successfully-pulled hub state (first run, or
        // the socket never completed a pull before), yet the hub now reports a NON-EMPTY
        // state. We cannot prove our buffered offline edit is newer than what's actually
        // on the device, so the conservative choice is to ADOPT the hub state and DROP
        // the buffered edit rather than silently clobber a possible device-side edit.
        // (An EMPTY pull carries nothing to clobber, so there we still keep our edit.)
        if (lastHub.isEmpty() && !pulled.isEmpty())
            return ReconcileAction::DropEdit;
        if (havePendingPush)
            return ReconcileAction::KeepAndPushEdit;
    }
    if (suppressed)
        return ReconcileAction::Ignore;
    return ReconcileAction::AdoptHub;
}
