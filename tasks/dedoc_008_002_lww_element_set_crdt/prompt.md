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
defmodule LWWSet do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  def add(server, element, timestamp) do
    validate_timestamp!(timestamp, :add)
    GenServer.call(server, {:add, element, timestamp})
  end

  def remove(server, element, timestamp) do
    validate_timestamp!(timestamp, :remove)
    GenServer.call(server, {:remove, element, timestamp})
  end

  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end

  def members(server) do
    GenServer.call(server, :members)
  end

  def merge(server, %{adds: adds, removes: removes} = _remote_state)
      when is_map(adds) and is_map(removes) do
    GenServer.call(server, {:merge, %{adds: adds, removes: removes}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :adds and :removes keys, got: #{inspect(invalid)}"
  end

  def state(server) do
    GenServer.call(server, :state)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, empty_state()}
  end

  @impl GenServer
  def handle_call({:add, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:adds, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
  end

  def handle_call({:remove, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:removes, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
  end

  def handle_call({:member?, element}, _from, state) do
    {:reply, element_present?(state, element), state}
  end

  def handle_call(:members, _from, state) do
    {:reply, compute_members(state), state}
  end

  def handle_call({:merge, remote}, _from, local) do
    {:reply, :ok, merge_states(local, remote)}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp empty_state, do: %{adds: %{}, removes: %{}}

  defp element_present?(%{adds: adds, removes: removes}, element) do
    case Map.fetch(adds, element) do
      {:ok, add_ts} ->
        remove_ts = Map.get(removes, element, 0)
        add_ts > remove_ts

      :error ->
        false
    end
  end

  defp compute_members(%{adds: adds, removes: removes}) do
    adds
    |> Enum.filter(fn {element, add_ts} ->
      remove_ts = Map.get(removes, element, 0)
      add_ts > remove_ts
    end)
    |> Enum.map(fn {element, _ts} -> element end)
    |> MapSet.new()
  end

  defp merge_states(%{adds: la, removes: lr}, %{adds: ra, removes: rr}) do
    %{
      adds: merge_ts_maps(la, ra),
      removes: merge_ts_maps(lr, rr)
    }
  end

  # Merges two timestamp maps by taking the per-element maximum.
  defp merge_ts_maps(local, remote) do
    Map.merge(local, remote, fn _element, l_ts, r_ts -> max(l_ts, r_ts) end)
  end

  defp validate_timestamp!(ts, _op) when is_integer(ts) and ts > 0, do: :ok

  defp validate_timestamp!(ts, op) do
    raise ArgumentError,
          "timestamp for #{op} must be a positive integer, got: #{inspect(ts)}"
  end
end
```
