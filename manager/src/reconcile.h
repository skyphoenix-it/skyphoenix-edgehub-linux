#pragma once

#include <QString>

// Decision for what to do with a UI-state document pulled from the hub over IPC,
// given the reconnect/suppression context. Pure — no I/O, no clock — so the
// reconnect state machine is testable with a decision table.
enum class ReconcileAction {
    AdoptHub,          // adopt the hub's pulled state (subject to the suppress check)
    KeepAndPushEdit,   // hub unchanged since we went offline → (re)push our buffered edit
    DropEdit,          // hub changed while we were offline → discard the stale buffered edit
    Ignore,            // inside the post-push suppression window → leave state untouched
};

// Decide the fate of a pulled state.
//   awaitingHub      — a buffered offline edit is waiting to be reconciled on the
//                      first pull after reconnecting.
//   havePendingPush  — a buffered offline edit actually exists.
//   pulled           — the UI-state the hub just sent us.
//   lastHub          — the last UI-state we knew the hub held.
//   suppressed       — nowMs < suppressAdoptUntilMs (a recent push we shouldn't clobber).
//
// When awaitingHub: if the hub's state changed while we were offline the buffered
// edit is stale (DropEdit). With NO prior baseline (lastHub empty) but a non-empty
// pull, we cannot prove our edit is newer than what's on the device, so we also
// DropEdit (adopt the hub) rather than clobber a possible device-side edit. An empty
// pull carries nothing to clobber, so there we (re)push our edit (KeepAndPushEdit).
// Outside the reconnect reconcile, adopt the hub state unless suppressed.
ReconcileAction reconcileOnPull(bool awaitingHub, bool havePendingPush,
                                const QString& pulled, const QString& lastHub,
                                bool suppressed);
