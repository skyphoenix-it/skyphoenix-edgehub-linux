import QtQuick
import QtTest
import "GuiUtil.js" as G

// ─────────────────────────────────────────────────────────────────────────────
// Regression guard for GuiUtil.eachItem's traversal.
//
// On 2026-07-19 the visible GUI suite drove qmltestrunner to 18.8 GB RSS and
// tripped the kernel OOM killer (which took IntelliJ down as collateral). Cause:
// eachItem walked both `children` and `data` with NO visited-set, so every node
// reachable by k distinct paths had its whole subtree re-walked k times. The real
// Manager tree: 1,701 unique nodes, >2,000,000 visits.
//
// These cases are deterministic and headless - no compositor, no Manager, no
// timing. They fail loudly if the seen-set is ever removed.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 10; height: 10

    // A "diamond" tree: `shared` is reachable through BOTH branches, and each
    // branch is itself reachable via children and via data. Without memoing,
    // visits grow multiplicatively with depth; with it, visits == unique nodes.
    Item {
        id: fixture
        Item {
            id: branchA
            Item { id: sharedHost; Item { id: leaf1 } Item { id: leaf2 } Item { id: leaf3 } }
        }
        Item {
            id: branchB
            // Re-reference the same subtree through the non-visual `data` list.
            data: [sharedHost]
        }
        Item {
            id: branchC
            data: [branchA, sharedHost]
        }
    }

    TestCase {
        name: "GuiUtilWalk"

        // THE guard: the walk must be linear - every node visited exactly once.
        function test_walk_visits_each_node_once() {
            var st = G.walkStats(fixture)
            verify(st.unique > 3, "fixture actually has a tree (" + st.unique + " nodes)")
            compare(st.calls, st.unique,
                    "eachItem must visit each node exactly once (calls=" + st.calls
                    + " unique=" + st.unique + "). calls>unique means the visited-set "
                    + "was removed - this is the OOM regression.")
        }

        // The teeth of the guard. Build a tree where each level is reachable by
        // two paths, so path count doubles per level: the pre-fix walk is
        // O(2^depth). At depth 16 that is >65,000 callbacks over ~50 nodes -
        // the same blow-up that reached 18.8 GB on the Manager tree. The fixed
        // walk is exactly linear, so this stays instant.
        function test_walk_is_linear_not_exponential() {
            var depth = 16
            var leaf = Qt.createQmlObject('import QtQuick; Item {}', root)
            var cur = leaf
            for (var i = 0; i < depth; i++) {
                // Two distinct parents of `cur`, both re-referencing it via data.
                var a = Qt.createQmlObject('import QtQuick; Item {}', root)
                var b = Qt.createQmlObject('import QtQuick; Item {}', root)
                a.data = [cur]
                b.data = [cur]
                var top = Qt.createQmlObject('import QtQuick; Item {}', root)
                top.data = [a, b]
                cur = top
            }
            var st = G.walkStats(cur)
            compare(st.calls, st.unique,
                    "walk must be linear: got calls=" + st.calls + " for unique="
                    + st.unique + " nodes at depth " + depth
                    + " (unmemoised this is ~2^" + depth + ")")
            verify(st.calls < 200, "linear walk stays small (calls=" + st.calls + ")")
        }

        // eachItem itself must call fn once per node, not once per path.
        function test_eachitem_callback_count_equals_unique() {
            var calls = 0, seen = []
            G.eachItem(fixture, function (n) {
                calls++
                verify(seen.indexOf(n) < 0, "node visited twice by eachItem")
                seen.push(n)
            })
            compare(calls, G.walkStats(fixture).unique, "one callback per unique node")
        }

        // A shared node reached via `data` is still found (the seen-set must not
        // prune reachability, only repetition).
        function test_data_only_nodes_are_still_reached() {
            var hit = null
            G.eachItem(fixture, function (n) { if (n === leaf3) hit = n })
            compare(hit, leaf3, "a node reachable only through `data` is still visited")
        }

        // collectPred must not return duplicates for a multiply-reachable node.
        function test_collect_has_no_duplicates() {
            var got = G.collectPred(fixture, function (n) { return n === sharedHost })
            compare(got.length, 1, "sharedHost collected exactly once despite 3 paths to it")
        }

        // findPred must stop as soon as it has a match rather than walking on.
        // Order-independent: abort on the very first node and require exactly one
        // callback. (Asserting on a named node would depend on traversal order -
        // branchA legitimately comes last.)
        function test_walk_aborts_when_fn_returns_true() {
            var visited = 0
            G.eachItem(fixture, function (n) { visited++; return true })
            compare(visited, 1, "returning true from fn must abort the walk immediately")
            compare(G.findPred(fixture, function (n) { return n === leaf2 }), leaf2,
                    "findPred still finds a deep node")
            compare(G.findPred(fixture, function (n) { return false }), null,
                    "findPred returns null when nothing matches")
        }
    }
}
