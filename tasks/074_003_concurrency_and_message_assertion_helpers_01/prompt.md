Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules. This set focuses on the **concurrency / message-passing model**: the current process mailbox and process liveness.

I need these macros:

- `assert_next_message(expected, timeout_ms \\ 1000)` — waits up to `timeout_ms` for the next message to arrive in the calling process's mailbox (consuming it) and asserts it equals `expected`. On failure there are two distinct cases: (a) a message arrived but did not match — show the expected and the received message; (b) no message arrived before the timeout — show the expected message and how long it waited.

- `assert_no_message(within_ms \\ 100)` — asserts that NO message arrives in the calling process's mailbox within `within_ms` milliseconds. On failure, show the message that unexpectedly arrived.

- `assert_process_exits(pid, timeout_ms \\ 1000)` — monitors `pid` and asserts that it terminates within `timeout_ms`. A process that is already dead counts as passing. On failure, show the pid, whether it is still alive, and how long it waited. Be sure to clean up the monitor on timeout so no stray `:DOWN` message is left behind.

All three must be macros (not plain functions) so that ExUnit can report the correct file and line number on failure. Use `ExUnit.Assertions.flunk/1` for surfacing failure messages. The module should be a single file with no external dependencies beyond `ExUnit`.

Give me the complete module in a single file.

## Additional interface contract

- In addition to the three macros, define a plain runtime FUNCTION `next_message(expected, timeout_ms)`: it waits up to `timeout_ms` for the next message in the calling process's mailbox and consumes it; it returns `:ok` when the message equals `expected`. On a non-matching message it must flunk with a failure message that includes both the expected and the received term; when no message arrives in time it must flunk with a failure message containing the phrase "timed out" and the `timeout_ms` value.
- Similarly define a plain runtime FUNCTION `no_message(timeout_ms)` mirroring `assert_no_message`: it returns `:ok` when no message arrives within `timeout_ms`; if a message does arrive it must flunk with a failure message that includes the received message (as rendered by `inspect/1`).
- Similarly define a plain runtime FUNCTION `process_exits(pid, timeout_ms)` mirroring `assert_process_exits`: it returns `:ok` when the process terminates within `timeout_ms` (an already-dead process counts as terminated), and on timeout it must flunk with a failure message that includes the phrase "did not terminate", the pid (as rendered by `inspect/1`), and whether the process is still alive (the boolean, e.g. `true`).
- The timeout parameter of each of the three runtime functions is optional and defaults to the same value as the corresponding macro: `next_message(expected, timeout_ms \\ 1000)`, `no_message(within_ms \\ 100)` and `process_exits(pid, timeout_ms \\ 1000)`. Calling `next_message(expected)`, `no_message()` or `process_exits(pid)` must behave exactly as if the default had been passed explicitly.
- On timeout, the failure message of `process_exits` must also include how long it waited — the `timeout_ms` value (so a bare `process_exits(pid)` that times out must report `1000`).
- When `no_message` (and therefore `assert_no_message`, which shares its failure path) does catch a message, the failure message must state the window it was watching in addition to the received term: it includes the `within_ms` value (so a bare `no_message()` or `assert_no_message()` that catches a message must report `100`).
