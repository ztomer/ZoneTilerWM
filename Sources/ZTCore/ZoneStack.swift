// ZoneStack.swift — pure stack-cycling logic. The windows that occupy one zone form a "stack";
// this picks the next/previous window id relative to the currently-focused one, wrapping around.
// The zone resolution, window enumeration (0 AX, CGWindowList) and the focus mutate live in the
// coordinator/adapters; this is just the index arithmetic, so it is fully unit-testable.

public enum ZoneStack {
    /// The window id adjacent to `focusedId` in `ordered`, stepping in `direction` (wrapping).
    /// Returns nil if the stack has fewer than two windows or the focused id isn't in it.
    public static func adjacent(focusedId: Int, ordered: [Int], direction: NavDirection) -> Int? {
        guard ordered.count >= 2, let idx = ordered.firstIndex(of: focusedId) else { return nil }
        let n = ordered.count
        let step = direction == .next ? 1 : -1
        let nextIdx = ((idx + step) % n + n) % n   // true modulo, so -1 wraps to n-1
        return ordered[nextIdx]
    }
}
