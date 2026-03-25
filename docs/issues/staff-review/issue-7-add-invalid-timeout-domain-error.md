## Title
Add invalid timeout domain error for ProcessRunner configuration

## Problem
`ProcessRunner` needs to reject invalid timeout values such as negative, zero, NaN, and infinity. The current error enum has no domain-specific case for this configuration failure.

## Impact
- Timeout validation cannot fail cleanly.
- Invalid configuration risks traps or undefined conversion behavior.
- Timeout-related failures blur configuration errors with runtime command timeouts.

## Proposed solution
1. Add `DependencyTrackerError.invalidTimeout(TimeInterval)`.
2. Validate timeout inputs before launching a subprocess.
3. Keep `commandTimedOut` reserved for valid timeouts that actually expire.

## Acceptance criteria
- [ ] Invalid timeout inputs return `DependencyTrackerError.invalidTimeout`.
- [ ] Invalid timeout values do not crash the process runner.
- [ ] Existing timeout-expiry behavior continues to use `commandTimedOut`.
