defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for the concurrency / message-passing model.

  This module bundles three assertions that operate on the *calling process's*
  mailbox and on process liveness:

    * `assert_next_message/2` — the next message to arrive must equal a term;
    * `assert_no_message/1` — no message may arrive within a window;
    * `assert_process_exits/2` — a process must terminate within a window.

  All three are macros so that ExUnit reports the failure at the caller's file
  and line rather than somewhere inside this module. Each macro delegates to a
  plain runtime function of the same name minus the `assert_` prefix
  (`next_message/2`, `no_message/1`, `process_exits/2`), which may also be
  called directly when a macro is inconvenient.

  ## Usage

      defmodule MyTest do
        use ExUnit.Case, async: true
        use AssertHelpers

        test "the worker pings us and then stops" do
          pid = spawn(fn -> send(self_pid(), :ping) end)
          assert_next_message(:ping)
          assert_no_message(50)
          assert_process_exits(pid)
        end
      end

  Failures are surfaced with `ExUnit.Assertions.flunk/1`, so the message text is
  fully under this module's control.
  """

  @default_message_timeout_ms 1_000
  @default_quiet_window_ms 100
  @default_exit_timeout_ms 1_000

  @doc """
  Imports the assertion macros of this module into the caller.

  Intended to be used from a test module:

      use AssertHelpers
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers,
        only: [
          assert_next_message: 1,
          assert_next_message: 2,
          assert_no_message: 0,
          assert_no_message: 1,
          assert_process_exits: 1,
          assert_process_exits: 2
        ]
    end
  end

  @doc """
  Asserts that the next message to arrive in the current process's mailbox
  equals `expected`.

  Waits up to `timeout_ms` milliseconds (default `#{@default_message_timeout_ms}`)
  for a message and consumes it. Fails if a message arrives but does not match,
  or if no message arrives before the timeout elapses.

      assert_next_message({:reply, :ok})
      assert_next_message(:tick, 250)
  """
  @spec assert_next_message(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_next_message(expected, timeout_ms \\ @default_message_timeout_ms) do
    quote do
      AssertHelpers.next_message(unquote(expected), unquote(timeout_ms))
    end
  end

  @doc """
  Asserts that no message arrives in the current process's mailbox within
  `within_ms` milliseconds (default `#{@default_quiet_window_ms}`).

  Fails as soon as any message is received, reporting the offending message and
  the window that was being watched.

      assert_no_message()
      assert_no_message(500)
  """
  @spec assert_no_message(Macro.t()) :: Macro.t()
  defmacro assert_no_message(within_ms \\ @default_quiet_window_ms) do
    quote do
      AssertHelpers.no_message(unquote(within_ms))
    end
  end

  @doc """
  Asserts that the process identified by `pid` terminates within `timeout_ms`
  milliseconds (default `#{@default_exit_timeout_ms}`).

  A process that is already dead counts as terminated. On timeout the monitor is
  demonitored with `[:flush]` so that no stray `:DOWN` message is left in the
  caller's mailbox.

      assert_process_exits(pid)
      assert_process_exits(pid, 5_000)
  """
  @spec assert_process_exits(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_process_exits(pid, timeout_ms \\ @default_exit_timeout_ms) do
    quote do
      AssertHelpers.process_exits(unquote(pid), unquote(timeout_ms))
    end
  end

  @doc """
  Runtime implementation behind `assert_next_message/2`.

  Waits up to `timeout_ms` milliseconds for the next message in the calling
  process's mailbox, consuming it, and returns `:ok` when it equals `expected`.
  Flunks with a descriptive message when the received term does not match, or
  when no message arrives in time.
  """
  @spec next_message(term(), non_neg_integer()) :: :ok
  def next_message(expected, timeout_ms \\ @default_message_timeout_ms) do
    receive do
      ^expected ->
        :ok

      other ->
        ExUnit.Assertions.flunk("""
        Expected the next message to match:

            #{inspect(expected)}

        but received:

            #{inspect(other)}
        """)
    after
      timeout_ms ->
        ExUnit.Assertions.flunk("""
        Expected to receive the message:

            #{inspect(expected)}

        but timed out after #{timeout_ms}ms with no message in the mailbox.
        """)
    end
  end

  @doc """
  Runtime implementation behind `assert_no_message/1`.

  Returns `:ok` when no message arrives in the calling process's mailbox within
  `within_ms` milliseconds. Flunks with the unexpected message (and the window
  being watched) as soon as one is received.
  """
  @spec no_message(non_neg_integer()) :: :ok
  def no_message(within_ms \\ @default_quiet_window_ms) do
    receive do
      message ->
        ExUnit.Assertions.flunk("""
        Expected no message within #{within_ms}ms, but received:

            #{inspect(message)}
        """)
    after
      within_ms ->
        :ok
    end
  end

  @doc """
  Runtime implementation behind `assert_process_exits/2`.

  Monitors `pid` and returns `:ok` when it terminates within `timeout_ms`
  milliseconds; an already-dead process counts as terminated. On timeout the
  monitor is flushed and the failure reports the pid, whether it is still alive
  and how long we waited.
  """
  @spec process_exits(pid(), non_neg_integer()) :: :ok
  def process_exits(pid, timeout_ms \\ @default_exit_timeout_ms) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} ->
        :ok
    after
      timeout_ms ->
        Process.demonitor(ref, [:flush])

        ExUnit.Assertions.flunk("""
        Expected process #{inspect(pid)} to exit, but it did not terminate \
        within #{timeout_ms}ms.

            pid:   #{inspect(pid)}
            alive: #{inspect(Process.alive?(pid))}
            waited: #{timeout_ms}ms
        """)
    end
  end
end