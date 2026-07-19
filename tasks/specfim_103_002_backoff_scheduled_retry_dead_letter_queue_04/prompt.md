# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`peek/3` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `peek/3`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `peek/3` missing

```elixir
defmodule BackoffDLQ do
  @moduledoc """
  A dead letter queue with exponential backoff-gated retries and a terminal
  `:dead` state after `:max_attempts` failures.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Pushes a failed `message` with backoff-scheduled retry. Returns `{:ok, id}`."
  @spec push(GenServer.server(), term(), term(), term(), map()) :: {:ok, term()}
  def push(server, queue_name, message, error_reason, metadata) when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end

  # TODO: @spec
  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @spec ready(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def ready(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:ready, queue_name, count})
  end

  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()} | {:error, :not_ready, non_neg_integer()}
  def retry(server, queue_name, message_id, handler_fn) when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end

  @spec purge(GenServer.server(), term(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      base: Keyword.get(opts, :base_backoff_ms, 1000),
      max_attempts: Keyword.get(opts, :max_attempts, 5),
      next_id: 0,
      queues: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, queue, message, error_reason, metadata}, _from, state) do
    id = state.next_id
    now = state.clock.()

    entry = %{
      id: id,
      message: message,
      error_reason: error_reason,
      metadata: metadata,
      retry_count: 0,
      status: :pending,
      pushed_at: now,
      next_retry_at: now
    }

    queues = Map.update(state.queues, queue, [entry], fn es -> es ++ [entry] end)
    {:reply, {:ok, id}, %{state | queues: queues, next_id: id + 1}}
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries = state.queues |> Map.get(queue, []) |> Enum.take(count) |> Enum.map(&public/1)
    {:reply, entries, state}
  end

  def handle_call({:ready, queue, count}, _from, state) do
    now = state.clock.()

    entries =
      state.queues
      |> Map.get(queue, [])
      |> Enum.filter(fn e -> e.status == :pending and now >= e.next_retry_at end)
      |> Enum.take(count)
      |> Enum.map(&public/1)

    {:reply, entries, state}
  end

  def handle_call({:retry, queue, id, handler}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    case Enum.find(entries, &(&1.id == id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :dead} ->
        {:reply, {:error, :dead}, state}

      entry ->
        now = state.clock.()

        if now < entry.next_retry_at do
          {:reply, {:error, :not_ready, entry.next_retry_at - now}, state}
        else
          case run_handler(handler, entry.message) do
            :success ->
              new = Enum.reject(entries, &(&1.id == id))
              {:reply, :ok, put_queue(state, queue, new)}

            {:failure, reason} ->
              rc = entry.retry_count + 1

              updated =
                if rc >= state.max_attempts do
                  %{entry | retry_count: rc, status: :dead}
                else
                  delay = state.base * pow2(rc - 1)
                  %{entry | retry_count: rc, next_retry_at: now + delay}
                end

              new = Enum.map(entries, fn e -> if e.id == id, do: updated, else: e end)
              {:reply, {:error, reason}, put_queue(state, queue, new)}
          end
        end
    end
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.pushed_at < older_than end)
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

  defp pow2(n), do: :math.pow(2, n) |> round()

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
      :message,
      :error_reason,
      :metadata,
      :retry_count,
      :status,
      :next_retry_at,
      :pushed_at
    ])
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
