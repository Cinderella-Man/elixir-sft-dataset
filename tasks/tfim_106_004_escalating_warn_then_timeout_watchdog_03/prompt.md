# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule EscalatingWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats with two escalation stages.

  Each registration has an early `warn_ms` deadline and a later `timeout_ms`
  deadline (measured from the last heartbeat or from registration). With no
  heartbeat, `on_warn_fn.(name)` fires once at `warn_ms` (moving the phase to
  `:warned`), and `on_timeout_fn.(name)` fires once at `timeout_ms`, after which the
  registration is removed. A heartbeat resets both deadlines and returns the phase to
  `:healthy`, so a heartbeat after a warning re-arms a fresh warn/timeout pair.

  Each generation of timers is tagged with a unique reference so stale timers (from a
  reset or an unregister) can never fire spuriously.
  """

  use GenServer

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Registers an escalating watchdog for `name`/`pid`: runs `on_warn_fn` after `warn_ms`
  of silence, then `on_timeout_fn` after `timeout_ms`. Returns `:ok`.
  """
  @spec register(
          term(),
          pid(),
          non_neg_integer(),
          non_neg_integer(),
          (term() -> any()),
          (term() -> any())
        ) :: :ok
  def register(name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn)
      when is_integer(warn_ms) and warn_ms >= 0 and is_integer(timeout_ms) and
             is_function(on_warn_fn, 1) and is_function(on_timeout_fn, 1) do
    unless warn_ms < timeout_ms do
      raise ArgumentError, "warn_ms must be strictly less than timeout_ms"
    end

    GenServer.call(
      __MODULE__,
      {:register, name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn}
    )
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec phase(term()) :: {:ok, :healthy | :warned} | {:error, :not_registered}
  def phase(name), do: GenServer.call(__MODULE__, {:phase, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  @impl true
  def handle_call(
        {:register, name, pid, warn_ms, timeout_ms, warn_fn, timeout_fn},
        _from,
        state
      ) do
    state = cancel_entry(state, name)

    entry =
      arm(
        %{
          pid: pid,
          warn_ms: warn_ms,
          timeout_ms: timeout_ms,
          warn_fn: warn_fn,
          timeout_fn: timeout_fn
        },
        name
      )

    {:reply, :ok, Map.put(state, name, entry)}
  end

  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        entry = entry |> disarm() |> arm(name)
        {:reply, :ok, Map.put(state, name, entry)}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:phase, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.phase}, state}
      :error -> {:reply, {:error, :not_registered}, state}
    end
  end

  @impl true
  def handle_info({:warn, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref, phase: :healthy} = entry} ->
        safe_invoke(entry.warn_fn, name)
        {:noreply, Map.put(state, name, %{entry | phase: :warned})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:timeout, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        safe_invoke(entry.timeout_fn, name)
        {:noreply, Map.delete(state, name)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp arm(entry, name) do
    ref = make_ref()
    warn_timer = Process.send_after(self(), {:warn, name, ref}, entry.warn_ms)
    timeout_timer = Process.send_after(self(), {:timeout, name, ref}, entry.timeout_ms)

    Map.merge(entry, %{
      ref: ref,
      phase: :healthy,
      warn_timer: warn_timer,
      timeout_timer: timeout_timer
    })
  end

  defp disarm(entry) do
    _ = Process.cancel_timer(entry.warn_timer)
    _ = Process.cancel_timer(entry.timeout_timer)
    entry
  end

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        disarm(entry)
        Map.delete(state, name)

      :error ->
        state
    end
  end

  defp safe_invoke(fun, name) do
    fun.(name)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule EscalatingWatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp warn_notifier(test_pid), do: fn name -> send(test_pid, {:warned, name}) end
  defp timeout_notifier(test_pid), do: fn name -> send(test_pid, {:timed_out, name}) end

  setup do
    start_supervised!({EscalatingWatchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # No escalation while heartbeats arrive
  # ------------------------------------------------------------------

  test "neither phase fires while heartbeats arrive within warn_ms" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        80,
        200,
        warn_notifier(test),
        timeout_notifier(test)
      )

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = EscalatingWatchdog.heartbeat(:w)
    end

    refute_receive {:warned, :w}, 60
    refute_receive {:timed_out, :w}, 10
  end

  # ------------------------------------------------------------------
  # Two-stage escalation
  # ------------------------------------------------------------------

  test "warn fires first, then timeout" do
    # TODO
  end

  test "phase transitions from healthy to warned" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        50,
        10_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)
    assert_receive {:warned, :w}, 1_000
    assert {:ok, :warned} = EscalatingWatchdog.phase(:w)
  end

  test "callbacks receive the registered name" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        {:svc, 9},
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, {:svc, 9}}, 1_000
    assert_receive {:timed_out, {:svc, 9}}, 1_000
  end

  # ------------------------------------------------------------------
  # Heartbeat resets escalation
  # ------------------------------------------------------------------

  test "heartbeat before warn prevents the warning in that window" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        80,
        400,
        warn_notifier(test),
        timeout_notifier(test)
      )

    Process.sleep(40)
    assert :ok = EscalatingWatchdog.heartbeat(:w)

    refute_receive {:warned, :w}, 60
  end

  test "heartbeat after warn re-arms so the warning can fire again and the timeout is deferred" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        50,
        250,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert :ok = EscalatingWatchdog.heartbeat(:w)
    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)

    # The warning re-arms and fires again from the fresh clock...
    assert_receive {:warned, :w}, 1_000
    # ...and the timeout has not fired because the clock was reset.
    refute_receive {:timed_out, :w}, 10

    assert :ok = EscalatingWatchdog.unregister(:w)
  end

  # ------------------------------------------------------------------
  # One-shot timeout removes the registration
  # ------------------------------------------------------------------

  test "timeout removes the registration and does not fire again" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:timed_out, :w}, 1_000
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:w)
    refute_receive {:timed_out, :w}, 200
  end

  # ------------------------------------------------------------------
  # Independence and unregister
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :fast,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    :ok =
      EscalatingWatchdog.register(
        :slow,
        dummy_pid(),
        5_000,
        10_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:timed_out, :fast}, 1_000
    refute_receive {:warned, :slow}, 50
  end

  test "unregister prevents both callbacks" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert :ok = EscalatingWatchdog.unregister(:w)

    refute_receive {:warned, :w}, 200
    refute_receive {:timed_out, :w}, 100
  end

  # ------------------------------------------------------------------
  # Validation and unknown-name behaviour
  # ------------------------------------------------------------------

  test "register raises when warn_ms is not strictly less than timeout_ms" do
    test = self()

    assert_raise ArgumentError, fn ->
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        100,
        100,
        warn_notifier(test),
        timeout_notifier(test)
      )
    end

    assert_raise ArgumentError, fn ->
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        200,
        100,
        warn_notifier(test),
        timeout_notifier(test)
      )
    end
  end

  test "phase and heartbeat for unknown names" do
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:nope)
    assert :ok = EscalatingWatchdog.heartbeat(:nope)
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    {:ok, pid} = EscalatingWatchdog.start_link(name: :custom_escalating)
    assert is_pid(pid)
    assert Process.whereis(:custom_escalating) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end
end
```
