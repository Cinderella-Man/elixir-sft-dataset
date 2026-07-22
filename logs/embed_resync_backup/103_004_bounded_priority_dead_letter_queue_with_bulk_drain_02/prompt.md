# Fill in the middle: `run_handler/2`

Implement the private `run_handler/2` function. It takes the caller-supplied
one-arity `handler` function and a `message`, invokes `handler.(message)`, and
normalizes the result into one of two internal outcome tuples that `drain/4`
knows how to act on:

- Treat `:ok` and `{:ok, term}` as success, returning `:success`.
- Treat `{:error, reason}` as a failure, returning `{:failure, reason}`.
- Treat any other return value `other` as a failure, returning
  `{:failure, {:unexpected_return, other}}`.

The handler is untrusted, so it must never crash the GenServer:

- If the handler **raises**, rescue the exception and return
  `{:failure, {:handler_raised, exception}}`.
- If the handler **throws or exits**, catch it and return `{:failure, {kind, value}}`
  where `kind`/`value` are the caught kind and value.

The function returns only these normalized outcomes and never propagates the
handler's failure.

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

  @doc """
  Pushes a dead-lettered `message` (with its `error_reason`, `metadata`, and `priority`)
  onto `queue_name`. Drops the lowest-priority entry when the bounded queue is full.
  """
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
      Enum.reduce(to_visit, {%{}, %{succeeded: 0, failed: 0, processed: []}}, fn
        entry, {out, acc} ->
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
    Map.take(e, [:id, :message, :error_reason, :metadata, :priority, :retry_count])
  end
end
```