# Fill in the middle: `DedupDLQ.run_handler/2`

Implement the private `run_handler/2` helper used by the `:retry` call. It receives
a one-arity `handler` function and the stored `message`, invokes `handler.(message)`,
and normalizes the result into one of two shapes the caller uses to decide whether to
remove or keep the entry:

- If the handler returns `:ok` or `{:ok, term}`, treat it as success and return
  `:success`.
- If the handler returns `{:error, reason}`, return `{:failure, reason}`.
- If the handler returns anything else, return `{:failure, {:unexpected_return, other}}`
  where `other` is that return value.
- The handler must never crash the process: if it **raises**, return
  `{:failure, {:handler_raised, exception}}`; if it **throws or exits**, catch the
  `kind` and `value` and return `{:failure, {kind, value}}`.

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
    # TODO
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
    Map.take(e, [:id, :dedup_key, :message, :error_reason, :metadata, :occurrences,
                 :retry_count, :first_seen, :last_seen])
  end
end
```