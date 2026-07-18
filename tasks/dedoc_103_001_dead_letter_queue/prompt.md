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
defmodule DLQ do
  use GenServer

  ## Client API

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts =
      case name do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def push(server, queue_name, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end

  def peek(server, queue_name, count)
      when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  def retry(server, queue_name, message_id, handler_fn)
      when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end

  def purge(server, queue_name, older_than)
      when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      next_id: 0,
      # queue_name => list of entries, kept in oldest-first insertion order
      queues: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, queue_name, message, error_reason, metadata}, _from, state) do
    id = state.next_id

    entry = %{
      id: id,
      message: message,
      error_reason: error_reason,
      metadata: metadata,
      retry_count: 0,
      pushed_at: state.clock.()
    }

    queues = Map.update(state.queues, queue_name, [entry], fn entries -> entries ++ [entry] end)
    state = %{state | queues: queues, next_id: id + 1}

    {:reply, {:ok, id}, state}
  end

  @impl true
  def handle_call({:peek, queue_name, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue_name, [])
      |> Enum.take(count)
      |> Enum.map(&public_entry/1)

    {:reply, entries, state}
  end

  @impl true
  def handle_call({:retry, queue_name, message_id, handler_fn}, _from, state) do
    entries = Map.get(state.queues, queue_name, [])

    case Enum.find(entries, fn entry -> entry.id == message_id end) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        case run_handler(handler_fn, entry.message) do
          :success ->
            new_entries = Enum.reject(entries, fn e -> e.id == message_id end)
            state = put_queue(state, queue_name, new_entries)
            {:reply, :ok, state}

          {:failure, reason} ->
            new_entries =
              Enum.map(entries, fn
                %{id: ^message_id} = e -> %{e | retry_count: e.retry_count + 1}
                e -> e
              end)

            state = put_queue(state, queue_name, new_entries)
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:purge, queue_name, older_than}, _from, state) do
    entries = Map.get(state.queues, queue_name, [])
    now = state.clock.()

    {kept, purged} =
      Enum.split_with(entries, fn entry ->
        now - entry.pushed_at < older_than
      end)

    state = put_queue(state, queue_name, kept)
    {:reply, {:ok, length(purged)}, state}
  end

  ## Helpers

  defp run_handler(handler_fn, message) do
    case handler_fn.(message) do
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

  defp put_queue(state, queue_name, entries) do
    queues =
      case entries do
        [] -> Map.delete(state.queues, queue_name)
        _ -> Map.put(state.queues, queue_name, entries)
      end

    %{state | queues: queues}
  end

  defp public_entry(entry) do
    Map.take(entry, [:id, :message, :error_reason, :metadata, :retry_count])
  end
end
```
