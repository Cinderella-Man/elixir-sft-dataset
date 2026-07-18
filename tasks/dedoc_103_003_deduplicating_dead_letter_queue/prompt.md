# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule DedupDLQ do
  use GenServer

  ## Client API

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def push(server, queue_name, dedup_key, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, dedup_key, message, error_reason, metadata})
  end

  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  def retry(server, queue_name, dedup_key, handler_fn) when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, dedup_key, handler_fn})
  end

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
