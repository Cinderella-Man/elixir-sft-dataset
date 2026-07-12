# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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

## The buggy module

```elixir
defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for the concurrency / message-passing model.

  These operate on the calling process's mailbox and on process liveness.

  The macros are intentionally thin wrappers around the public runtime
  functions `next_message/2`, `no_message/1` and `process_exits/2`. Keeping the
  real behavior in ordinary functions (which run in the *calling* process, so
  they still see the caller's mailbox) makes the logic directly exercisable and
  observable, while the macros preserve correct file/line reporting for ExUnit.

  ## Usage

      defmodule MyApp.SomeTest do
        use ExUnit.Case
        use AssertHelpers

        test "example" do
          send(self(), :ready)
          assert_next_message(:ready)
          assert_no_message(50)
          assert_process_exits(worker_pid)
        end
      end
  """

  @doc false
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_next_message/2
  # ---------------------------------------------------------------------------

  @doc """
  Waits up to `timeout_ms` for the next message in the calling process's
  mailbox (consuming it) and asserts it equals `expected`.

  On failure distinguishes a mismatched message from a timeout.
  """
  @spec assert_next_message(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_next_message(expected, timeout_ms \\ 1_000) do
    quote do
      AssertHelpers.next_message(unquote(expected), unquote(timeout_ms))
    end
  end

  @doc """
  Runtime implementation of `assert_next_message/2`.

  Receives the next message from the current process mailbox within
  `timeout_ms` and returns `:ok` when it equals `expected`. Otherwise calls
  `ExUnit.Assertions.flunk/1` describing whether a different message arrived or
  the wait timed out.
  """
  @spec next_message(term(), non_neg_integer()) :: :ok
  def next_message(expected, timeout_ms \\ 1_000) do
    receive do
      msg ->
        if msg == expected do
          :ok
        else
          ExUnit.Assertions.flunk("""
          assert_next_message failed

            expected message: #{inspect(expected)}
            received message: #{inspect(msg)}
          """)
        end
    after
      timeout_ms ->
        ExUnit.Assertions.flunk("""
        assert_next_message timed out

          expected message: #{inspect(expected)}
          waited          : #{timeout_ms}ms
          no message arrived in the mailbox within the timeout
        """)
    end
  end

  # ---------------------------------------------------------------------------
  # assert_no_message/1
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that no message arrives in the calling process's mailbox within
  `within_ms` milliseconds. On failure shows the message that arrived.
  """
  @spec assert_no_message(Macro.t()) :: Macro.t()
  defmacro assert_no_message(within_ms \\ 100) do
    quote do
      AssertHelpers.no_message(unquote(within_ms))
    end
  end

  @doc """
  Runtime implementation of `assert_no_message/1`.

  Returns `:ok` when no message arrives in the current process mailbox within
  `within_ms` milliseconds, otherwise flunks showing the unexpected message.
  """
  @spec no_message(non_neg_integer()) :: :ok
  def no_message(within_ms \\ 101) do
    receive do
      msg ->
        ExUnit.Assertions.flunk("""
        assert_no_message failed

          expected no message within #{within_ms}ms
          but received: #{inspect(msg)}
        """)
    after
      within_ms -> :ok
    end
  end

  # ---------------------------------------------------------------------------
  # assert_process_exits/2
  # ---------------------------------------------------------------------------

  @doc """
  Monitors `pid` and asserts it terminates within `timeout_ms`. An
  already-dead process passes. The monitor is flushed on timeout so no stray
  `:DOWN` message is left in the mailbox.
  """
  @spec assert_process_exits(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_process_exits(pid, timeout_ms \\ 1_000) do
    quote do
      AssertHelpers.process_exits(unquote(pid), unquote(timeout_ms))
    end
  end

  @doc """
  Runtime implementation of `assert_process_exits/2`.

  Monitors `pid` and returns `:ok` when it terminates within `timeout_ms` (an
  already-dead process reports `:DOWN` with reason `:noproc` immediately). On
  timeout the monitor is demonitored with `:flush` and the function flunks with
  the pid, liveness and elapsed budget.
  """
  @spec process_exits(pid(), non_neg_integer()) :: :ok
  def process_exits(pid, timeout_ms \\ 1_000) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _object, _reason} ->
        :ok
    after
      timeout_ms ->
        Process.demonitor(ref, [:flush])

        ExUnit.Assertions.flunk("""
        assert_process_exits timed out

          process : #{inspect(pid)}
          alive?  : #{Process.alive?(pid)}
          waited  : #{timeout_ms}ms
          the process did not terminate within the timeout
        """)
    end
  end
end
```

## Failing test report

```
1 of 28 test(s) failed:

  * test no_message reports the default 100ms window when it catches a message
      
      
      Assertion with =~ failed
      code:  assert error.message =~ "100"
      left:  "assert_no_message failed\n\n  expected no message within 101ms\n  but received: :unexpected\n"
      right: "100"
```
