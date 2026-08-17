# Changelog

## 0.0.1

- initial version
- `Scheduler` class: epoch-aligned recurring timer that runs an asynchronous
  handler every `intervalSeconds` (optionally shifted by `biasSeconds`),
  serializing runs (`isExecutingHandler`) and resetting a per-run `counter` on
  every `start` / `startImmediately`; `start`/`startImmediately`/`stop` control
  the timer and `nextExecutionAt`/`isRunning`/`timerId` inspect its state
- `nextExecutionAt` and `initialDelaySeconds`: pure epoch-alignment arithmetic
  taking the current time explicitly, so the alignment logic is unit-testable
  without a running timer
- tests: `test/scheduler.test.mo` covering the alignment math (epoch alignment,
  bias, sub-second handling, delay/next agreement, daily interval)
