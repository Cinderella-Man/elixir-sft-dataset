# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule AssertHelpersTest do
  use ExUnit.Case, async: false
  use AssertHelpers

  describe "assert_next_message/2" do
    test "passes when the expected message is the next one" do
      send(self(), {:hello, 1})
      assert_next_message({:hello, 1})
    end

    test "passes when the message arrives slightly later" do
      parent = self()

      spawn(fn ->
        Process.sleep(20)
        send(parent, :ping)
      end)

      assert_next_message(:ping, 500)
    end

    test "fails when a different message arrives" do
      send(self(), :unexpected)

      result =
        try do
          assert_next_message(:wanted)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "unexpected"
      assert result =~ "wanted"
    end

    test "fails when no message arrives before the timeout" do
      result =
        try do
          assert_next_message(:never, 50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "timed out" or result =~ "50"
    end
  end

  describe "next_message/2 (runtime function)" do
    test "returns :ok when the expected message is next" do
      # TODO
    end

    test "consumes the message it matched" do
      send(self(), :only_one)
      assert AssertHelpers.next_message(:only_one, 500) == :ok
      # Mailbox must be empty now, so a follow-up wait must time out (flunk).
      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.next_message(:only_one, 30)
      end
    end

    test "flunks with expected and received on a mismatch" do
      send(self(), :unexpected)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.next_message(:wanted, 100)
        end

      assert error.message =~ "unexpected"
      assert error.message =~ "wanted"
    end

    test "flunks on timeout when the mailbox stays empty" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.next_message(:never, 40)
        end

      assert error.message =~ "timed out"
      assert error.message =~ "40"
    end
  end

  describe "assert_no_message/1" do
    test "passes when the mailbox stays empty" do
      assert_no_message(50)
    end

    test "fails when a message arrives within the window" do
      send(self(), :surprise)

      result =
        try do
          assert_no_message(50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "surprise"
    end
  end

  describe "no_message/1 (runtime function)" do
    test "returns :ok when nothing arrives" do
      assert AssertHelpers.no_message(40) == :ok
    end

    test "flunks showing the message that unexpectedly arrived" do
      send(self(), :surprise)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.no_message(50)
        end

      assert error.message =~ "surprise"
    end
  end

  describe "assert_process_exits/2" do
    test "passes when the process terminates in time" do
      pid = spawn(fn -> Process.sleep(20) end)
      assert_process_exits(pid, 500)
    end

    test "passes immediately for an already-dead process" do
      pid = spawn(fn -> :ok end)
      Process.sleep(20)
      refute Process.alive?(pid)
      assert_process_exits(pid, 200)
    end

    test "fails when the process outlives the timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      result =
        try do
          assert_process_exits(pid, 50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "did not terminate" or result =~ "50"

      Process.exit(pid, :kill)
    end

    test "does not leave a stray :DOWN message after a timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      _ =
        try do
          assert_process_exits(pid, 50)
        rescue
          _ -> :ok
        end

      Process.exit(pid, :kill)

      # The monitor should have been flushed, so no :DOWN is waiting.
      assert_no_message(80)
    end
  end

  describe "process_exits/2 (runtime function)" do
    test "returns :ok when the process terminates in time" do
      pid = spawn(fn -> Process.sleep(20) end)
      assert AssertHelpers.process_exits(pid, 500) == :ok
    end

    test "returns :ok immediately for an already-dead process" do
      pid = spawn(fn -> :ok end)
      Process.sleep(20)
      refute Process.alive?(pid)
      assert AssertHelpers.process_exits(pid, 200) == :ok
    end

    test "flunks with pid and liveness when the process outlives the timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.process_exits(pid, 50)
        end

      assert error.message =~ "did not terminate"
      assert error.message =~ inspect(pid)
      assert error.message =~ "true"

      Process.exit(pid, :kill)
    end

    test "flushes the monitor so no stray :DOWN remains after a timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.process_exits(pid, 50)
      end

      Process.exit(pid, :kill)
      # If the monitor were not flushed, a :DOWN would now be waiting.
      assert AssertHelpers.no_message(80) == :ok
    end
  end

  # The prompt pins `assert_next_message(expected, timeout_ms \\ 1000)` and
  # requires the timeout failure to show how long it waited, so with no
  # timeout argument the failure must report the default of 1000.
  test "assert_next_message waits the documented default of 1000ms and reports it" do
    result =
      try do
        assert_next_message(:never)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
    assert result =~ "1000"
  end

  # The prompt pins `assert_process_exits(pid, timeout_ms \\ 1000)` and
  # requires the failure to show how long it waited, so with no timeout
  # argument the failure must report the default of 1000.
  test "assert_process_exits waits the documented default of 1000ms and reports it" do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    result =
      try do
        assert_process_exits(pid)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    Process.exit(pid, :kill)

    refute result == :no_failure
    assert result =~ inspect(pid)
    # Check the reported wait outside the pid text so a pid that happens to
    # contain the digits 1000 cannot satisfy the assertion.
    assert String.replace(result, inspect(pid), "") =~ "1000"
  end

  # The prompt pins `next_message(expected, timeout_ms \\ 1000)` and requires
  # the timeout failure message to contain the phrase "timed out" and the
  # `timeout_ms` value, so a bare next_message/1 call that times out must
  # report the default of 1000.
  test "next_message waits the documented default of 1000ms and reports it" do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.next_message(:never_sent)
      end

    assert error.message =~ "timed out"
    assert error.message =~ "1000"
  end

  # The prompt pins `no_message(within_ms \\ 100)` and only allows `:ok` once
  # no message has arrived within the window, so a bare no_message/0 call on
  # an empty mailbox must watch the mailbox for at least the default 100ms
  # before returning :ok. Lower bound only — an upper bound would be flaky.
  # BEAM guarantees a receive timeout never fires early, so taking the
  # minimum over a few runs sharpens the measurement without ever failing a
  # correct implementation.
  test "no_message watches the mailbox for at least the documented default of 100ms" do
    min_elapsed_us =
      1..5
      |> Enum.map(fn _ ->
        started = System.monotonic_time(:microsecond)
        assert AssertHelpers.no_message() == :ok
        System.monotonic_time(:microsecond) - started
      end)
      |> Enum.min()

    assert min_elapsed_us >= 100_000
  end

  # The prompt pins `assert_no_message(within_ms \\ 100)` and the macro
  # asserts that NO message arrives within `within_ms`, so a bare
  # assert_no_message() on an empty mailbox must watch the mailbox for at
  # least the default 100ms before passing. (Lower bound only, as above.)
  test "assert_no_message watches the mailbox for at least the documented default of 100ms" do
    min_elapsed_us =
      1..5
      |> Enum.map(fn _ ->
        started = System.monotonic_time(:microsecond)
        assert_no_message()
        System.monotonic_time(:microsecond) - started
      end)
      |> Enum.min()

    assert min_elapsed_us >= 100_000
  end

  # The prompt pins `process_exits(pid, timeout_ms \\ 1000)` and requires the
  # timeout failure message to include the phrase "did not terminate", the
  # pid, the liveness boolean and how long it waited (the `timeout_ms` value),
  # so a bare process_exits/1 call must report the default of 1000.
  test "process_exits waits the documented default of 1000ms and reports it" do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.process_exits(pid)
      end

    Process.exit(pid, :kill)

    assert error.message =~ "did not terminate"
    assert error.message =~ inspect(pid)
    # Check the reported wait outside the pid text so a pid that happens to
    # contain the digits 1000 cannot satisfy the assertion.
    assert String.replace(error.message, inspect(pid), "") =~ "1000"
  end

  # The prompt requires no_message's failure message, when a message IS
  # caught, to state the window it was watching — the `within_ms` value — so
  # a bare no_message/0 that catches a message must report the default of
  # 100. Zero timing dependence: the message is pre-sent.
  test "no_message reports the default 100ms window when it catches a message" do
    send(self(), :unexpected)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.no_message()
      end

    assert error.message =~ "100"
    assert error.message =~ ":unexpected"
  end

  # Same contract through the macro: a bare assert_no_message() that catches
  # a message must report the default window of 100ms.
  test "assert_no_message reports the default 100ms window when it catches a message" do
    send(self(), :unexpected)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_no_message()
      end

    assert error.message =~ "100"
    assert error.message =~ ":unexpected"
  end

  test "assert_next_message timeout failure shows the expected term and the wait" do
    result =
      try do
        assert_next_message(:never_arrives, 50)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
    assert result =~ ":never_arrives"
    assert result =~ "50"
  end

  test "assert_process_exits failure shows the pid, its liveness and the wait" do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    result =
      try do
        assert_process_exits(pid, 50)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    Process.exit(pid, :kill)

    refute result == :no_failure
    assert result =~ inspect(pid)
    # Strip the pid text so its digits cannot satisfy the wait/liveness checks.
    without_pid = String.replace(result, inspect(pid), "")
    assert without_pid =~ "true"
    assert without_pid =~ "50"
  end

  test "assert_next_message consumes the message it matched" do
    send(self(), :consumed_by_macro)
    assert_next_message(:consumed_by_macro, 200)
    # If the matched message were left behind, this window would catch it.
    assert_no_message(50)
  end

  test "the three assertion entry points are macros at both documented arities" do
    assert macro_exported?(AssertHelpers, :assert_next_message, 1)
    assert macro_exported?(AssertHelpers, :assert_next_message, 2)
    assert macro_exported?(AssertHelpers, :assert_no_message, 0)
    assert macro_exported?(AssertHelpers, :assert_no_message, 1)
    assert macro_exported?(AssertHelpers, :assert_process_exits, 1)
    assert macro_exported?(AssertHelpers, :assert_process_exits, 2)

    refute function_exported?(AssertHelpers, :assert_next_message, 2)
    refute function_exported?(AssertHelpers, :assert_no_message, 1)
    refute function_exported?(AssertHelpers, :assert_process_exits, 2)
  end

  test "next_message/1 returns :ok for an already queued matching message" do
    send(self(), {:queued, 7})
    assert AssertHelpers.next_message({:queued, 7}) == :ok
  end

  test "process_exits/1 returns :ok for a process that has already terminated" do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 500
    refute Process.alive?(pid)

    assert AssertHelpers.process_exits(pid) == :ok
  end
end
```
