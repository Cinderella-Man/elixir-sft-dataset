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
defmodule CacheLayer do
  use GenServer

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {neg, gen_opts} = Keyword.pop(opts, :negative_hits, 3)

    unless is_integer(neg) and neg >= 0 do
      raise ArgumentError,
            ":negative_hits must be a non-negative integer, got: #{inspect(neg)}"
    end

    GenServer.start_link(__MODULE__, %{negative_hits: neg}, gen_opts)
  end

  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        GenServer.call(server, {:fetch, table, key, fallback_fn})

      tid ->
        case :ets.lookup(tid, key) do
          # Fast path: a cached success can be served without the GenServer.
          [{^key, {:ok, value}}] -> {:ok, value}
          # Misses and negative entries need serialised handling.
          _ -> GenServer.call(server, {:fetch, table, key, fallback_fn})
        end
    end
  end

  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end

  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl GenServer
  def init(%{negative_hits: neg}) do
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}, negative_hits: neg}}
  end

  @impl GenServer
  def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    reply =
      case :ets.lookup(tid, key) do
        [{^key, {:ok, value}}] ->
          {:ok, value}

        [{^key, {:neg, reason, remaining}}] ->
          if remaining <= 1 do
            :ets.delete(tid, key)
          else
            :ets.insert(tid, {key, {:neg, reason, remaining - 1}})
          end

          {:error, reason}

        [] ->
          case fallback_fn.() do
            {:ok, value} ->
              :ets.insert(tid, {key, {:ok, value}})
              {:ok, value}

            {:error, reason} ->
              if state.negative_hits > 0 do
                :ets.insert(tid, {key, {:neg, reason, state.negative_hits}})
              end

              {:error, reason}

            other ->
              raise ArgumentError,
                    "fallback_fn must return {:ok, value} or {:error, reason}, " <>
                      "got: #{inspect(other)}"
          end
      end

    {:reply, reply, state}
  end

  def handle_call({:invalidate, table, key}, _from, state) do
    case Map.get(state.tables, table) do
      nil -> :ok
      tid -> :ets.delete(tid, key)
    end

    {:reply, :ok, state}
  end

  def handle_call({:invalidate_all, table}, _from, state) do
    case Map.get(state.tables, table) do
      nil -> :ok
      tid -> :ets.delete_all_objects(tid)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    pid = self()

    Enum.each(state.tables, fn {table, tid} ->
      :persistent_term.erase({__MODULE__, pid, table})
      :ets.delete(tid)
    end)

    :ok
  end

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------

  defp ensure_table(table, %{tables: tables} = state) do
    case Map.get(tables, table) do
      nil ->
        tid = :ets.new(table, [:set, :public])
        :persistent_term.put({__MODULE__, self(), table}, tid)
        {tid, %{state | tables: Map.put(tables, table, tid)}}

      tid ->
        {tid, state}
    end
  end

  defp resolve_pid!(pid) when is_pid(pid), do: pid

  defp resolve_pid!(name) do
    case GenServer.whereis(name) do
      nil -> raise ArgumentError, "CacheLayer: cannot resolve #{inspect(name)} to a pid"
      pid -> pid
    end
  end
end
```
