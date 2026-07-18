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
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        # Table has not been created yet; let the GenServer handle everything,
        # including table creation.
        GenServer.call(server, {:fetch, table, key, fallback_fn})

      tid ->
        # Table exists — try a direct ETS read (no GenServer involved).
        case :ets.lookup(tid, key) do
          [{^key, value}] ->
            {:ok, value}

          [] ->
            # Cache miss: serialise through the GenServer so only one caller
            # runs the fallback.
            GenServer.call(server, {:fetch, table, key, fallback_fn})
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
  def init(:ok) do
    # Trap exits so `terminate/2` is reliably called, giving us a chance to
    # clean up :persistent_term entries even if the supervisor shuts us down.
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}}}
  end

  @impl GenServer
  # Fetch — serialised write path (also handles first-time table creation).
  def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    # Re-check ETS before invoking the fallback: a concurrent caller that also
    # missed the cache and ended up here first may have already populated it.
    value =
      case :ets.lookup(tid, key) do
        [{^key, cached}] ->
          cached

        [] ->
          fresh = fallback_fn.()
          :ets.insert(tid, {key, fresh})
          fresh
      end

    {:reply, {:ok, value}, state}
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

    # Delete each ETS table (which also frees its memory) and remove the
    # corresponding :persistent_term entry so stale tids cannot leak to callers
    # that somehow still hold a reference to this (now-dead) server.
    Enum.each(state.tables, fn {table, tid} ->
      :persistent_term.erase({__MODULE__, pid, table})
      :ets.delete(tid)
    end)

    :ok
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  # Returns the tid for `table`, creating the ETS table if this is the first
  # time we have seen this atom. Publishing via :persistent_term is done here
  # so `fetch/4` can find the tid on the next call without hitting the GenServer.
  defp ensure_table(table, %{tables: tables} = state) do
    case Map.get(tables, table) do
      nil ->
        # Named tables would collide if multiple CacheLayer instances use the
        # same atom, so we use unnamed tables and track tids ourselves.
        tid = :ets.new(table, [:set, :public])

        # Publish so fetch/4 can bypass the GenServer on future cache hits.
        :persistent_term.put({__MODULE__, self(), table}, tid)

        new_state = %{state | tables: Map.put(tables, table, tid)}
        {tid, new_state}

      tid ->
        {tid, state}
    end
  end

  # Resolve any valid GenServer.server() reference to a concrete pid.
  defp resolve_pid!(pid) when is_pid(pid), do: pid

  defp resolve_pid!(name) do
    case GenServer.whereis(name) do
      nil -> raise ArgumentError, "CacheLayer: cannot resolve #{inspect(name)} to a pid"
      pid -> pid
    end
  end
end
```
