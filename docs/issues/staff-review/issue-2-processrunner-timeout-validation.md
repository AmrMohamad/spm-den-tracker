## Title
Harden `ProcessRunner` timeout conversion against invalid `TimeInterval` values

## Problem
`timeoutNanoseconds(for:)` converts `TimeInterval` to `UInt64` directly. Invalid values (negative, zero, NaN, very large) can cause traps or undefined behavior.

## Impact
- Configuration/input errors can crash process execution.
- Potential reliability issues in CI and long-running automation.

## Proposed solution
1. Validate timeout (`isFinite && timeout > 0`).
2. Throw domain-specific error for invalid timeout values.
3. Clamp extreme valid values or reject explicitly with controlled error.

## Acceptance criteria
- [ ] Unit tests for negative, zero, NaN, and extremely large timeout inputs.
- [ ] Invalid timeout values return controlled errors instead of crashes.
- [ ] Existing command timeout behavior remains unchanged for valid values.
