# Fix the failing module

I asked for the following:

Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules. This set focuses on the **concurrency / message-passing model**: the current process mailbox and process liveness.

I need these macros:

- `assert_next_message(expected, timeout_ms \\ 1000)` — waits up to `timeout_ms` for the next message to arrive in the calling process's mailbox (consuming it) and asserts it equals `expected`. On failure there are two distinct cases: (a) a message arrived but did not match — show the expected and the received message; (b) no message arrived before the timeout — show the expected message and how long it waited.

- `assert_no_message(within_ms \\ 100)` — asserts that NO message arrives in the calling process's mailbox within `within_ms` milliseconds. On failure, show the message that unexpectedly arrived.

- `assert_process_exits(pid, timeout_ms \\ 1000)` — monitors `pid` and asserts that it terminates within `timeout_ms`. A process that is already dead counts as passing. On failure, show the pid, whether it is still alive, and how long it waited. Be sure to clean up the monitor on timeout so no stray `:DOWN` message is left behind.

All three must be macros (not plain functions) so that ExUnit can report the correct file and line number on failure. Use `ExUnit.Assertions.flunk/1` for surfacing failure messages. The module should be a single file with no external dependencies beyond `ExUnit`.

Give me the complete module in a single file.

Here is my current implementation, but it is failing tests:

```elixir
defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for the concurrency / message-passing model.

  These operate on the calling process's mailbox and on process liveness.

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
    quote bind_quoted: [expected: expected, timeout_ms: timeout_ms] do
      receive do
        msg ->
          unless msg == expected do
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
    quote bind_quoted: [within_ms: within_ms] do
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
    quote bind_quoted: [pid: pid, timeout_ms: timeout_ms] do
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
end
```

The failure report:

```
Mutation gate failed: the whole-module raise-mutant graded inconclusively (mutant compile failure, harness load error, or eval timeout) — coverage cannot be verified. Strengthen test_harness.exs so it fails when that code is gutted (add assertions that actually exercise the behavior) — do not weaken the implementation.
```

Find the bug and give me the corrected complete module in a single file.
<!-- minted from logs/attempts/074_003_concurrency_and_message_assertion_helpers_01/attempt_1 -->
