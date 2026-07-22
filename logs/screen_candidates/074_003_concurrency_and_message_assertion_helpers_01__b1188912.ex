defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for the concurrency / message-passing model.

  This module is meant to be `use`d inside a test module:

      defmodule MyTest do
        use ExUnit.Case, async: true
        use AssertHelpers

        test "mailbox" do
          send(self(), :ping)
          assert_next_message(:ping)
          assert_no_message()
        end
      end

  It provides three macros — `assert_next_message/2`, `assert_no_message/1`
  and `assert_process_exits/2` — that inspect the calling process's mailbox
  and process liveness. They are macros (rather than plain functions) so that
  ExUnit reports the correct file and line on failure.

  For programmatic use, three mirror runtime functions are also exported:
  `next_message/2`, `no_message/1` and `process_exits/2`.

  All failures are surfaced through `ExUnit.Assertions.flunk/1`.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @doc """
  Imports the assertion macros and helper functions into the caller.

  Intended to be invoked as `use AssertHelpers` from a test module.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Waits up to `timeout_ms` for the next mailbox message (consuming it) and
  asserts it equals `expected`.

  On failure it distinguishes two cases: a message arrived but did not match
  (both the expected and received terms are shown), or no message arrived
  before the timeout (the expected term and the wait time are shown).
  """
  @spec assert_next_message(Macro.t()) :: Macro.t()
  @spec assert_next_message(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_next_message(expected, timeout_ms \\ 1000) do
    quote do
      expected = unquote(expected)
      timeout = unquote(timeout_ms)

      receive do
        ^expected ->
          :ok

        msg ->
          ExUnit.Assertions.flunk("""
          Expected next message to match:
              #{inspect(expected)}
          but received:
              #{inspect(msg)}
          """)
      after
        timeout ->
          ExUnit.Assertions.flunk("""
          Expected to receive message:
              #{inspect(expected)}
          but timed out after #{timeout}ms.
          """)
      end
    end
  end

  @doc """
  Asserts that NO message arrives in the calling process's mailbox within
  `within_ms` milliseconds.

  On failure, the message that unexpectedly arrived is shown.
  """
  @spec assert_no_message() :: Macro.t()
  @spec assert_no_message(Macro.t()) :: Macro.t()
  defmacro assert_no_message(within_ms \\ 100) do
    quote do
      within = unquote(within_ms)

      receive do
        msg ->
          ExUnit.Assertions.flunk("""
          Expected no message within #{within}ms, but received:
              #{inspect(msg)}
          """)
      after
        within ->
          :ok
      end
    end
  end

  @doc """
  Monitors `pid` and asserts that it terminates within `timeout_ms`.

  A process that is already dead counts as passing. On failure, the pid,
  whether it is still alive, and how long it waited are shown. The monitor is
  always cleaned up (with `:flush`) so no stray `:DOWN` message is left behind.
  """
  @spec assert_process_exits(Macro.t()) :: Macro.t()
  @spec assert_process_exits(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_process_exits(pid, timeout_ms \\ 1000) do
    quote do
      pid = unquote(pid)
      timeout = unquote(timeout_ms)
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, _object, _reason} ->
          :ok
      after
        timeout ->
          Process.demonitor(ref, [:flush])
          alive = Process.alive?(pid)

          ExUnit.Assertions.flunk("""
          Expected process #{inspect(pid)} to exit within #{timeout}ms.
          Still alive?: #{alive}
          """)
      end
    end
  end

  @doc """
  Runtime mirror of `assert_next_message/2`.

  Waits up to `timeout_ms` for the next mailbox message, consumes it and
  returns `:ok` when it equals `expected`. Flunks with both the expected and
  received terms on a mismatch, or with a message containing "timed out" and
  `timeout_ms` when nothing arrives in time.
  """
  @spec next_message(term(), non_neg_integer()) :: :ok
  def next_message(expected, timeout_ms) do
    receive do
      ^expected ->
        :ok

      msg ->
        flunk("""
        Expected next message to match:
            #{inspect(expected)}
        but received:
            #{inspect(msg)}
        """)
    after
      timeout_ms ->
        flunk("""
        Expected to receive message:
            #{inspect(expected)}
        but timed out after #{timeout_ms}ms.
        """)
    end
  end

  @doc """
  Runtime mirror of `assert_no_message/1`.

  Returns `:ok` when no message arrives within `timeout_ms`. If a message does
  arrive, flunks with a failure message that includes it (via `inspect/1`).
  """
  @spec no_message(non_neg_integer()) :: :ok
  def no_message(timeout_ms) do
    receive do
      msg ->
        flunk("""
        Expected no message within #{timeout_ms}ms, but received:
            #{inspect(msg)}
        """)
    after
      timeout_ms ->
        :ok
    end
  end

  @doc """
  Runtime mirror of `assert_process_exits/2`.

  Monitors `pid` and returns `:ok` when it terminates within `timeout_ms` (an
  already-dead process counts as terminated). On timeout, cleans up the monitor
  and flunks with a message containing "did not terminate", the pid (via
  `inspect/1`) and whether the process is still alive (the boolean).
  """
  @spec process_exits(pid(), non_neg_integer()) :: :ok
  def process_exits(pid, timeout_ms) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _object, _reason} ->
        :ok
    after
      timeout_ms ->
        Process.demonitor(ref, [:flush])
        alive = Process.alive?(pid)

        flunk("""
        Process #{inspect(pid)} did not terminate within #{timeout_ms}ms.
        Still alive?: #{alive}
        """)
    end
  end
end