# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DedupDLQ do
  @moduledoc """
  A dead letter queue that coalesces repeated failures of the same logical
  message by a `dedup_key`, tracking an occurrence count and first/last-seen
  timestamps instead of storing duplicate entries.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Pushes a failed `message`, deduplicating by `dedup_key`. Returns
  `{:ok, :new, id}` for a first occurrence or `{:ok, :duplicate, id}` when the
  key is already queued.
  """
  @spec push(GenServer.server(), term(), term(), term(), term(), map()) ::
          {:ok, :new | :duplicate, term()}
  def push(server, queue_name, dedup_key, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, dedup_key, message, error_reason, metadata})
  end

  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()}
  def retry(server, queue_name, dedup_key, handler_fn) when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, dedup_key, handler_fn})
  end

  @spec purge(GenServer.server(), term(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {:ok, %{clock: clock, next_id: 0, queues: %{}}}
  end

  @impl true
  def handle_call({:push, queue, key, message, error_reason, metadata}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()

    case Enum.find(entries, &(&1.dedup_key == key)) do
      nil ->
        id = state.next_id

        entry = %{
          id: id,
          dedup_key: key,
          message: message,
          error_reason: error_reason,
          metadata: metadata,
          occurrences: 1,
          retry_count: 0,
          first_seen: now,
          last_seen: now
        }

        state = put_queue(%{state | next_id: id + 1}, queue, entries ++ [entry])
        {:reply, {:ok, :new, id}, state}

      existing ->
        updated = %{
          existing
          | occurrences: existing.occurrences + 1,
            last_seen: now,
            message: message,
            error_reason: error_reason,
            metadata: metadata
        }

        new = Enum.map(entries, fn e -> if e.dedup_key == key, do: updated, else: e end)
        {:reply, {:ok, :duplicate, existing.id}, put_queue(state, queue, new)}
    end
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries = state.queues |> Map.get(queue, []) |> Enum.take(count) |> Enum.map(&public/1)
    {:reply, entries, state}
  end

  def handle_call({:retry, queue, key, handler}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    case Enum.find(entries, &(&1.dedup_key == key)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        case run_handler(handler, entry.message) do
          :success ->
            new = Enum.reject(entries, &(&1.dedup_key == key))
            {:reply, :ok, put_queue(state, queue, new)}

          {:failure, reason} ->
            new =
              Enum.map(entries, fn
                %{dedup_key: ^key} = e -> %{e | retry_count: e.retry_count + 1}
                e -> e
              end)

            {:reply, {:error, reason}, put_queue(state, queue, new)}
        end
    end
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.last_seen < older_than end)
    {:reply, {:ok, length(purged)}, put_queue(state, queue, kept)}
  end

  ## Helpers

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
    Map.take(e, [
      :id,
      :dedup_key,
      :message,
      :error_reason,
      :metadata,
      :occurrences,
      :retry_count,
      :first_seen,
      :last_seen
    ])
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DedupDLQTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  setup do
    start_supervised!({Clock, 0})
    {:ok, pid} = DedupDLQ.start_link(clock: &Clock.now/0)
    %{dlq: pid}
  end

  test "first push creates a new entry with occurrences 1", %{dlq: dlq} do
    assert {:ok, :new, id} = DedupDLQ.push(dlq, "orders", "k1", %{n: 1}, :timeout, %{src: "web"})
    assert [e] = DedupDLQ.peek(dlq, "orders", 10)
    assert e.id == id
    assert e.dedup_key == "k1"
    assert e.occurrences == 1
    assert e.retry_count == 0
    assert e.first_seen == 0
    assert e.last_seen == 0
  end

  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert DedupDLQ.peek(dlq, "nope", 10) == []
  end

  test "repeated key coalesces: same id, bumped count, latest data", %{dlq: dlq} do
    {:ok, :new, id} = DedupDLQ.push(dlq, "q", "k", :first, :err_a, %{v: 1})
    Clock.advance(100)
    assert {:ok, :duplicate, ^id} = DedupDLQ.push(dlq, "q", "k", :second, :err_b, %{v: 2})

    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.occurrences == 2
    assert e.message == :second
    assert e.error_reason == :err_b
    assert e.metadata == %{v: 2}
    assert e.first_seen == 0
    assert e.last_seen == 100
  end

  test "different keys are independent entries", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :ma, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :mb, :err, %{})
    assert length(DedupDLQ.peek(dlq, "q", 10)) == 2
  end

  test "peek orders oldest-first by first_seen", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :first, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :second, :err, %{})
    # re-push "a" as duplicate — must NOT reorder it to the back
    Clock.advance(1)
    {:ok, :duplicate, _} = DedupDLQ.push(dlq, "q", "a", :first, :err, %{})

    assert Enum.map(DedupDLQ.peek(dlq, "q", 10), & &1.dedup_key) == ["a", "b"]
  end

  test "peek truncates to count, keeping the oldest entries", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :ma, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :mb, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "c", :mc, :err, %{})

    assert Enum.map(DedupDLQ.peek(dlq, "q", 2), & &1.dedup_key) == ["a", "b"]
    assert Enum.map(DedupDLQ.peek(dlq, "q", 1), & &1.dedup_key) == ["a"]
    assert DedupDLQ.peek(dlq, "q", 0) == []
    # peeking is non-destructive: all three are still queued
    assert length(DedupDLQ.peek(dlq, "q", 3)) == 3
  end

  test "retry success removes the coalesced entry", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert :ok = DedupDLQ.retry(dlq, "q", "k", fn _ -> :ok end)
    assert DedupDLQ.peek(dlq, "q", 10) == []
  end

  test "retry failure keeps entry and bumps retry_count (not occurrences)", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, :boom} = DedupDLQ.retry(dlq, "q", "k", fn _ -> {:error, :boom} end)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.occurrences == 1
  end

  test "duplicate push after a failed retry preserves retry_count", %{dlq: dlq} do
    {:ok, :new, id} = DedupDLQ.push(dlq, "q", "k", :first, :err_a, %{v: 1})
    assert {:error, :boom} = DedupDLQ.retry(dlq, "q", "k", fn _ -> {:error, :boom} end)

    Clock.advance(30)
    assert {:ok, :duplicate, ^id} = DedupDLQ.push(dlq, "q", "k", :second, :err_b, %{v: 2})

    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.occurrences == 2
    assert e.id == id
    assert e.first_seen == 0
    assert e.last_seen == 30
    assert e.message == :second
  end

  test "raising handler counts as failure without crashing", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, _} = DedupDLQ.retry(dlq, "q", "k", fn _ -> raise "x" end)
    assert Process.alive?(dlq)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "retry on unknown dedup key returns :not_found", %{dlq: dlq} do
    assert {:error, :not_found} = DedupDLQ.retry(dlq, "q", "nope", fn _ -> :ok end)
  end

  test "purge is based on last_seen; a recent duplicate protects the entry", %{dlq: dlq} do
    # TODO
  end

  test "queues are independent for the same dedup key", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "a", "k", :ma, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "b", "k", :mb, :err, %{})
    assert [ea] = DedupDLQ.peek(dlq, "a", 10)
    assert [eb] = DedupDLQ.peek(dlq, "b", 10)
    assert ea.message == :ma
    assert eb.message == :mb
  end
end
```
