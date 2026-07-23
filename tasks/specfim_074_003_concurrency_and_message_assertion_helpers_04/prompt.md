# Fill in one @spec

Below: a working module where the `@spec` for
`next_message/2` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `next_message/2` missing

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
  # TODO: @spec
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
  def no_message(within_ms \\ 100) do
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

The `@spec` attribute only — nothing more.
