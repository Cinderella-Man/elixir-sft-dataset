# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule EdgeDebouncer do
  @moduledoc """
  A `GenServer` that debounces zero-arity function calls on a per-key basis with
  a configurable firing edge: `:trailing` (default), `:leading`, or `:both`.

  A *burst* for a key begins with a `call/4` when the key has no pending timer
  and ends after `delay_ms` of quiet. The edge chosen by the first call of the
  burst decides when the function(s) run:

    * `:trailing` — only the most recent func runs, once, after the burst settles.
    * `:leading`  — the first func runs immediately; nothing runs at the end.
    * `:both`     — the first func runs immediately, and if any further calls
      arrived the most recent func also runs once at the end (a lone call fires
      leading only, never twice).
  """

  use GenServer

  @valid_edges [:trailing, :leading, :both]

  @doc """
  Starts the debouncer. Accepts a `:name` option for registration, defaulting to
  `EdgeDebouncer`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Handles a debounced `func` for `key`. `opts` may include `:edge`
  (`:trailing` | `:leading` | `:both`, default `:trailing`). Returns `:ok`
  promptly. Raises `ArgumentError` for an invalid edge.
  """
  @spec call(term(), non_neg_integer(), (-> any()), keyword()) :: :ok
  def call(key, delay_ms, func, opts \\ [])
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) and is_list(opts) do
    edge = Keyword.get(opts, :edge, :trailing)

    unless edge in @valid_edges do
      raise ArgumentError,
            "invalid :edge #{inspect(edge)}, expected one of #{inspect(@valid_edges)}"
    end

    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func, edge})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, func, edge}, state) do
    case Map.get(state, key) do
      nil ->
        # First call of a new burst: leading edges fire immediately.
        if edge in [:leading, :both], do: run(func)
        entry = Map.merge(arm(key, delay_ms), %{edge: edge, calls: 1, last_func: func})
        {:noreply, Map.put(state, key, entry)}

      %{timer: ref} = entry ->
        # cancel_timer/1 can return false with the old {:fire, …} already
        # sitting in the mailbox — the fresh token below makes that stale
        # message a no-op instead of an early trailing fire.
        Process.cancel_timer(ref)
        entry = %{entry | calls: entry.calls + 1, last_func: func}
        entry = Map.merge(entry, arm(key, delay_ms))
        {:noreply, Map.put(state, key, entry)}
    end
  end

  @impl true
  def handle_info({:fire, key, token}, state) do
    case Map.get(state, key) do
      # Only the CURRENT burst's token may fire; a stale timer message from a
      # superseded burst (its cancel arrived too late) is discarded.
      %{token: ^token} = entry ->
        cond do
          entry.edge == :trailing -> run(entry.last_func)
          entry.edge == :both and entry.calls > 1 -> run(entry.last_func)
          true -> :ok
        end

        {:noreply, Map.delete(state, key)}

      _ ->
        {:noreply, state}
    end
  end

  # Arm the burst's timer under a fresh token; {:fire, key, token} only acts
  # while the entry still carries this exact token.
  defp arm(key, delay_ms) do
    token = make_ref()
    %{timer: Process.send_after(self(), {:fire, key, token}, delay_ms), token: token}
  end

  # Run the func off the server's reduction path.
  defp run(func), do: spawn(fn -> func.() end)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule EdgeDebouncerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(EdgeDebouncer)
    :ok
  end

  defp notify(tag) do
    test = self()
    fn -> send(test, tag) end
  end

  # -------------------------------------------------------
  # Trailing edge (default)
  # -------------------------------------------------------

  test "trailing edge coalesces to the last func after the delay" do
    EdgeDebouncer.call("k", 150, notify({:ran, 1}))
    EdgeDebouncer.call("k", 150, notify({:ran, 2}))
    EdgeDebouncer.call("k", 150, notify({:ran, 3}), edge: :trailing)

    assert_receive {:ran, 3}, 600
    refute_received {:ran, 1}
    refute_received {:ran, 2}
    refute_receive {:ran, _}, 250
  end

  test "trailing edge does not run before the delay elapses" do
    EdgeDebouncer.call("k", 200, notify(:done))
    refute_receive :done, 120
    assert_receive :done, 400
  end

  # -------------------------------------------------------
  # Leading edge
  # -------------------------------------------------------

  test "leading edge runs the first func immediately and nothing else" do
    EdgeDebouncer.call("k", 200, notify({:ran, 1}), edge: :leading)
    EdgeDebouncer.call("k", 200, notify({:ran, 2}), edge: :leading)
    EdgeDebouncer.call("k", 200, notify({:ran, 3}), edge: :leading)

    # First func fires right away.
    assert_receive {:ran, 1}, 100
    # No later func ever runs, and no trailing execution occurs.
    refute_receive {:ran, 2}, 400
    refute_received {:ran, 3}
  end

  # -------------------------------------------------------
  # Both edges
  # -------------------------------------------------------

  test "both edges fire leading immediately and trailing at the end" do
    EdgeDebouncer.call("k", 150, notify({:ran, 1}), edge: :both)
    EdgeDebouncer.call("k", 150, notify({:ran, 2}), edge: :both)
    EdgeDebouncer.call("k", 150, notify({:ran, 3}), edge: :both)

    # Leading is the first func.
    assert_receive {:ran, 1}, 100
    # Trailing is the most recent func.
    assert_receive {:ran, 3}, 600
    # The middle func never runs.
    refute_received {:ran, 2}
  end

  test "both edges with a single call fires leading only (never twice)" do
    EdgeDebouncer.call("k", 150, notify(:solo), edge: :both)

    assert_receive :solo, 100
    # No trailing execution for a lone call.
    refute_receive :solo, 400
  end

  # -------------------------------------------------------
  # Independence + fresh bursts
  # -------------------------------------------------------

  test "different keys are independent" do
    EdgeDebouncer.call("a", 100, notify({:key, "a"}), edge: :leading)
    EdgeDebouncer.call("b", 100, notify({:key, "b"}))

    assert_receive {:key, "a"}, 100
    assert_receive {:key, "b"}, 400
  end

  test "a fresh burst after settling fires leading again" do
    EdgeDebouncer.call("k", 100, notify(:first), edge: :leading)
    assert_receive :first, 100

    # Let the burst settle.
    Process.sleep(200)

    EdgeDebouncer.call("k", 100, notify(:second), edge: :leading)
    assert_receive :second, 100
  end

  # -------------------------------------------------------
  # Contract
  # -------------------------------------------------------

  test "call/4 returns :ok and does not block on the func" do
    slow = fn ->
      Process.sleep(300)
      :ok
    end

    {micros, :ok} = :timer.tc(fn -> EdgeDebouncer.call("s", 50, slow) end)
    assert micros < 100_000
  end

  test "invalid edge raises ArgumentError" do
    # TODO
  end

  # -------------------------------------------------------
  # Funcs run off the server's reduction path
  # -------------------------------------------------------

  test "a leading func that never returns does not wedge the server" do
    test = self()

    # Blocks forever until explicitly released, without sleeping the test.
    blocking = fn ->
      send(test, {:blocking_started, self()})

      receive do
        :release -> :ok
      end
    end

    EdgeDebouncer.call("blocked", 100, blocking, edge: :leading)
    assert_receive {:blocking_started, blocker}, 500

    # While that func is still running, the server keeps handling other keys:
    # a leading call fires immediately and a trailing call still settles.
    EdgeDebouncer.call("other", 100, notify(:other_leading), edge: :leading)
    assert_receive :other_leading, 500

    EdgeDebouncer.call("later", 80, notify(:other_trailing))
    assert_receive :other_trailing, 600

    send(blocker, :release)
  end

  @tag :capture_log
  test "a raising func does not crash the server" do
    server = Process.whereis(EdgeDebouncer)

    EdgeDebouncer.call("boom_lead", 50, fn -> raise "boom" end, edge: :leading)
    EdgeDebouncer.call("boom_trail", 50, fn -> raise "boom" end)

    # This trailing execution lands after the raising trailing func has fired.
    EdgeDebouncer.call("ok", 100, notify(:settled))
    assert_receive :settled, 600

    # The same process is still registered and still debouncing new bursts.
    assert Process.whereis(EdgeDebouncer) == server

    EdgeDebouncer.call("alive", 50, notify(:alive), edge: :leading)
    assert_receive :alive, 300
  end

  test "a second call restarts the delay so trailing survives the original deadline" do
    # t0: arm a 200ms trailing burst for "k".
    EdgeDebouncer.call("k", 200, notify(:late))

    # A separate key acts as a deterministic ~120ms clock (keys are independent).
    EdgeDebouncer.call("clock", 120, notify(:tick))
    assert_receive :tick, 500

    # ~t0+120: re-call "k" — the deadline must restart from now (~t0+320),
    # not stay at the original ~t0+200.
    EdgeDebouncer.call("k", 200, notify(:late))
    refute_receive :late, 120

    assert_receive :late, 500
  end

  test "the opening call's edge wins over a later call's edge option" do
    EdgeDebouncer.call("k", 150, notify(:lead), edge: :leading)
    EdgeDebouncer.call("k", 150, notify(:tail), edge: :trailing)

    # The burst was opened as :leading, so the first func fires immediately...
    assert_receive :lead, 200
    # ...and no trailing execution occurs even though a later call said :trailing.
    refute_receive :tail, 500
  end

  test "a settled :both burst leaves no state and the next call fires leading again" do
    EdgeDebouncer.call("k", 100, notify({:b, 1}), edge: :both)
    EdgeDebouncer.call("k", 100, notify({:b, 2}), edge: :both)

    assert_receive {:b, 1}, 200
    # Trailing arriving means the burst has settled and the key is cleared.
    assert_receive {:b, 2}, 500

    EdgeDebouncer.call("k", 100, notify({:b, 3}), edge: :both)
    assert_receive {:b, 3}, 200
  end

  test "the :both trailing func runs exactly once when the burst settles" do
    EdgeDebouncer.call("k", 100, notify(:x), edge: :both)
    EdgeDebouncer.call("k", 100, notify(:x), edge: :both)

    # Leading, then exactly one trailing — never a third execution.
    assert_receive :x, 200
    assert_receive :x, 500
    refute_receive :x, 300
  end

  test "start_link/1 registers under a custom :name and returns {:ok, pid}" do
    assert {:ok, pid} = EdgeDebouncer.start_link(name: :edge_debouncer_alt)

    assert Process.whereis(:edge_debouncer_alt) == pid
    # The default-named process from setup/1 is a distinct registration.
    assert Process.whereis(EdgeDebouncer) != pid
  end

  # -------------------------------------------------------
  # A stuck or crashing func cannot stall its own burst
  # -------------------------------------------------------

  test "a leading func stuck forever still lets its own burst's trailing run" do
    test = self()

    # Never returns until released, so a func executed on the server's own
    # reduction path would hold the burst's timer hostage forever.
    blocking = fn ->
      send(test, {:leading_started, self()})

      receive do
        :release -> :ok
      end
    end

    EdgeDebouncer.call("k", 100, blocking, edge: :both)
    assert_receive {:leading_started, blocker}, 500

    # A second call in the same burst means a trailing execution is owed.
    EdgeDebouncer.call("k", 100, notify(:trailing_ran), edge: :both)
    assert_receive :trailing_ran, 600

    send(blocker, :release)
  end

  @tag :capture_log
  test "a raising leading func still lets its own burst's trailing run" do
    EdgeDebouncer.call("k", 80, fn -> raise "boom" end, edge: :both)
    EdgeDebouncer.call("k", 80, notify(:trailing_ran), edge: :both)

    # The leading crash neither kills the server nor cancels the trailing edge.
    assert_receive :trailing_ran, 600
  end

  @tag :capture_log
  test "a raising trailing func leaves the key clear for a brand-new burst" do
    EdgeDebouncer.call("k", 60, fn -> raise "boom" end)

    # The burst that crashed must still have settled and cleared its key, so
    # the next call opens a fresh burst and fires leading immediately.
    EdgeDebouncer.call("clock", 200, notify(:tick))
    assert_receive :tick, 600

    EdgeDebouncer.call("k", 100, notify(:fresh_lead), edge: :leading)
    assert_receive :fresh_lead, 300
  end
end
```
