defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros focused on Elixir's concurrency /
  message-passing model: the current process mailbox and process liveness.

  `use AssertHelpers` inside a test module to import the macros:

      defmodule MyTest do
        use ExUnit.Case
        use AssertHelpers

        test "receives ping" do
          send(self(), :ping)
          assert_next_message(:ping)
        end
      end

  The public assertions are defined as macros (rather than plain functions)
  so that ExUnit reports the failing file and line at the call site instead
  of somewhere inside this module. Two plain runtime functions,
  `next_message/2` and `process_exits/2`, mirror the mailbox and liveness
  assertions for callers that need an ordinary function boundary.

  All failures are surfaced with `ExUnit.Assertions.flunk/1`. The module has
  no dependencies beyond `ExUnit`.
  """

  @doc """
  Imports the assertion macros into the calling (test) module.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Waits up to `timeout_ms` for the next message in the calling process's
  mailbox (consuming it) and asserts that it equals `expected`.

  On failure there are two distinct cases:

    * a message arrived but did not match — the expected and received terms
      are both shown;
    * no message arrived before the timeout — the expected message and how
      long it waited are shown.
  """
  @spec assert_next_message(Macro.t()) :: Macro.t()
  @spec assert_next_message(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_next_message(expected, timeout_ms \\ 1000) do
    quote do
      expected = unquote(expected)
      timeout = unquote(timeout_ms)

      receive do
        received ->
          if received == expected do
            :ok
          else
            ExUnit.Assertions.flunk(
              "expected next message #{inspect(expected)}, " <>
                "but received #{inspect(received)}"
            )
          end
      after
        timeout ->
          ExUnit.Assertions.flunk(
            "expected next message #{inspect(expected)}, " <>
              "but no message arrived within #{timeout}ms"
          )
      end
    end
  end

  @doc """
  Asserts that NO message arrives in the calling process's mailbox within
  `within_ms` milliseconds.

  On failure, the message that unexpectedly arrived is shown.
  """
  @spec assert_no_message(Macro.t()) :: Macro.t()
  defmacro assert_no_message(within_ms \\ 100) do
    quote do
      within = unquote(within_ms)

      receive do
        received ->
          ExUnit.Assertions.flunk(
            "expected no message within #{within}ms, " <>
              "but received #{inspect(received)}"
          )
      after
        within -> :ok
      end
    end
  end

  @doc """
  Monitors `pid` and asserts that it terminates within `timeout_ms`.

  A process that is already dead counts as passing. On timeout the monitor
  is cleaned up (with `:flush`) so no stray `:DOWN` message is left behind,
  and the failure shows the pid, whether it is still alive, and how long the
  assertion waited.
  """
  @spec assert_process_exits(Macro.t()) :: Macro.t()
  @spec assert_process_exits(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_process_exits(pid, timeout_ms \\ 1000) do
    quote do
      pid = unquote(pid)
      timeout = unquote(timeout_ms)
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} ->
          :ok
      after
        timeout ->
          Process.demonitor(ref, [:flush])

          ExUnit.Assertions.flunk(
            "expected process #{inspect(pid)} to exit within #{timeout}ms, " <>
              "but it is still alive? #{Process.alive?(pid)} after #{timeout}ms"
          )
      end
    end
  end

  @doc """
  Waits up to `timeout_ms` for the next message in the calling process's
  mailbox, consuming it, and returns `:ok` when it equals `expected`.

  On a non-matching message it flunks with a message that includes both the
  expected and received terms. When no message arrives in time it flunks
  with a message containing the phrase "timed out" and the `timeout_ms`
  value.
  """
  @spec next_message(term(), non_neg_integer()) :: :ok
  def next_message(expected, timeout_ms) do
    receive do
      received ->
        if received == expected do
          :ok
        else
          ExUnit.Assertions.flunk(
            "expected next message #{inspect(expected)}, " <>
              "but received #{inspect(received)}"
          )
        end
    after
      timeout_ms ->
        ExUnit.Assertions.flunk(
          "next_message timed out after #{timeout_ms}ms " <>
            "waiting for #{inspect(expected)}"
        )
    end
  end

  @doc """
  Monitors `pid` and returns `:ok` when the process terminates within
  `timeout_ms` (an already-dead process counts as terminated).

  On timeout the monitor is cleaned up (with `:flush`) and it flunks with a
  message that includes the phrase "did not terminate", the pid (as rendered
  by `inspect/1`), and whether the process is still alive (the boolean).
  """
  @spec process_exits(pid(), non_neg_integer()) :: :ok
  def process_exits(pid, timeout_ms) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} ->
        :ok
    after
      timeout_ms ->
        Process.demonitor(ref, [:flush])

        ExUnit.Assertions.flunk(
          "process #{inspect(pid)} did not terminate within #{timeout_ms}ms " <>
            "(still alive? #{Process.alive?(pid)})"
        )
    end
  end
end