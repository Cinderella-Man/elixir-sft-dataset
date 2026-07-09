# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PriorityDLQ do
  @moduledoc """
  A bounded, priority-ordered dead letter queue supporting bulk reprocessing
  via `drain/4`. Entries are visited highest-priority-first, FIFO within a
  priority level.
  """

  use GenServer

  @rank %{high: 3, normal: 2, low: 1}

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec push(GenServer.server(), term(), term(), term(), map(), :high | :normal | :low) ::
          {:ok, term()} | {:error, :full}
  def push(server, queue_name, message, error_reason, metadata, priority)
      when is_map(metadata) and priority in [:high, :normal, :low] do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata, priority})
  end

  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @spec drain(GenServer.server(), term(), (term() -> term()), non_neg_integer()) ::
          {:ok, %{succeeded: non_neg_integer(), failed: non_neg_integer(), processed: [term()]}}
  def drain(server, queue_name, handler_fn, count)
      when is_function(handler_fn, 1) and is_integer(count) and count >= 0 do
    GenServer.call(server, {:drain, queue_name, handler_fn, count})
  end

  @spec purge(GenServer.server(), term(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    capacity = Keyword.get(opts, :capacity, :infinity)
    {:ok, %{clock: clock, capacity: capacity, next_id: 0, queues: %{}}}
  end

  @impl true
  def handle_call({:push, queue, message, error_reason, metadata, priority}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    if full?(state.capacity, length(entries)) do
      {:reply, {:error, :full}, state}
    else
      id = state.next_id

      entry = %{
        id: id,
        message: message,
        error_reason: error_reason,
        metadata: metadata,
        priority: priority,
        retry_count: 0,
        pushed_at: state.clock.()
      }

      state = put_queue(%{state | next_id: id + 1}, queue, entries ++ [entry])
      {:reply, {:ok, id}, state}
    end
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue, [])
      |> ordered()
      |> Enum.take(count)
      |> Enum.map(&public/1)

    {:reply, entries, state}
  end

  def handle_call({:drain, queue, handler, count}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    to_visit = entries |> ordered() |> Enum.take(count)

    {outcomes, stats} =
      Enum.reduce(to_visit, {%{}, %{succeeded: 0, failed: 0, processed: []}}, fn entry,
                                                                                 {out, acc} ->
        acc = %{acc | processed: acc.processed ++ [entry.id]}

        case run_handler(handler, entry.message) do
          :success ->
            {Map.put(out, entry.id, :remove), %{acc | succeeded: acc.succeeded + 1}}

          {:failure, _reason} ->
            {Map.put(out, entry.id, {:keep, entry.retry_count + 1}),
             %{acc | failed: acc.failed + 1}}
        end
      end)

    new_entries =
      entries
      |> Enum.reduce([], fn e, acc ->
        case Map.get(outcomes, e.id) do
          :remove -> acc
          {:keep, rc} -> [%{e | retry_count: rc} | acc]
          nil -> [e | acc]
        end
      end)
      |> Enum.reverse()

    {:reply, {:ok, stats}, put_queue(state, queue, new_entries)}
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.pushed_at < older_than end)
    {:reply, {:ok, length(purged)}, put_queue(state, queue, kept)}
  end

  ## Helpers

  defp full?(:infinity, _len), do: false
  defp full?(cap, len) when is_integer(cap), do: len >= cap

  # highest priority first, then FIFO (ascending id = insertion order)
  defp ordered(entries) do
    Enum.sort_by(entries, fn e -> {-Map.fetch!(@rank, e.priority), e.id} end)
  end

  defp run_handler(handler, message) do
    case handler.(message) do
      :ok -> :success
      {:ok, _term} -> :success
      {:error, reason} -> {:failure, reason}
      other -> {:failure, {:unexpected_return, other}}
    end
  rescue
    exception -> {:failure, {:handler_raised, exception}}
  catch
    kind, value -> {:failure, {kind, value}}
  end

  defp put_queue(state, queue, entries) do
    queues =
      case entries do
        [] -> Map.delete(state.queues, queue)
        _ -> Map.put(state.queues, queue, entries)
      end

    %{state | queues: queues}
  end

  defp public(e) do
    Map.take(e, [:id, :message, :error_reason, :metadata, :priority, :retry_count])
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PriorityDLQTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  defmodule Recorder do
    use Agent
    def start_link(_ \\ nil), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(m), do: Agent.update(__MODULE__, &[m | &1])
    def order, do: Agent.get(__MODULE__, &Enum.reverse(&1))
  end

  setup do
    start_supervised!({Clock, 0})
    start_supervised!(Recorder)
    {:ok, pid} = PriorityDLQ.start_link(clock: &Clock.now/0)
    %{dlq: pid}
  end

  test "push stores with priority and retry_count 0; peek returns it", %{dlq: dlq} do
    # TODO
  end

  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert PriorityDLQ.peek(dlq, "nope", 10) == []
  end

  test "peek orders by priority then FIFO within a priority", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :n1, :err, %{}, :normal)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h2, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l2, :err, %{}, :low)

    assert Enum.map(PriorityDLQ.peek(dlq, "q", 10), & &1.message) ==
             [:h1, :h2, :n1, :l1, :l2]
  end

  test "peek respects count in priority order", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    assert Enum.map(PriorityDLQ.peek(dlq, "q", 1), & &1.message) == [:h1]
  end

  test "capacity is enforced per queue and rejects when full (nothing stored)", %{} do
    {:ok, dlq} = PriorityDLQ.start_link(clock: &Clock.now/0, capacity: 2)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :a, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :b, :err, %{}, :low)
    assert {:error, :full} = PriorityDLQ.push(dlq, "q", :c, :err, %{}, :high)
    assert length(PriorityDLQ.peek(dlq, "q", 10)) == 2

    # other queue has its own budget
    assert {:ok, _} = PriorityDLQ.push(dlq, "other", :d, :err, %{}, :low)
  end

  test "drain visits in priority order and reports processed ids in that order", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, hid} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    {:ok, nid} = PriorityDLQ.push(dlq, "q", :n1, :err, %{}, :normal)

    handler = fn msg ->
      Recorder.record(msg)
      :ok
    end

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", handler, 2)

    assert Recorder.order() == [:h1, :n1]
    assert stats.succeeded == 2
    assert stats.failed == 0
    assert stats.processed == [hid, nid]

    # low priority one remains
    assert Enum.map(PriorityDLQ.peek(dlq, "q", 10), & &1.message) == [:l1]
  end

  test "drain removes successes and keeps failures (bumping retry_count)", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :ok_msg, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :fail_msg, :err, %{}, :normal)

    handler = fn
      :ok_msg -> :ok
      :fail_msg -> {:error, :boom}
    end

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", handler, 10)
    assert stats.succeeded == 1
    assert stats.failed == 1

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.message == :fail_msg
    assert e.retry_count == 1
  end

  test "a raising handler during drain does not crash the process", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :boom, :err, %{}, :high)
    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> raise "x" end, 10)
    assert stats.failed == 1
    assert Process.alive?(dlq)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "purge removes by age", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :old, :err, %{}, :high)
    Clock.advance(1000)
    {:ok, b} = PriorityDLQ.push(dlq, "q", :new, :err, %{}, :low)

    assert {:ok, 1} = PriorityDLQ.purge(dlq, "q", 500)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == b
  end

  test "queues are independent", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "a", :ma, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "b", :mb, :err, %{}, :low)

    assert {:ok, %{succeeded: 1}} = PriorityDLQ.drain(dlq, "a", fn _ -> :ok end, 10)
    assert PriorityDLQ.peek(dlq, "a", 10) == []
    assert [%{message: :mb}] = PriorityDLQ.peek(dlq, "b", 10)
  end
end
```
