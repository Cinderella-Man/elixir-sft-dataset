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
defmodule TwoPhaseSet do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  def add(server, element) do
    case GenServer.call(server, {:add, element}) do
      :ok ->
        :ok

      {:error, :tombstoned} ->
        raise ArgumentError,
              "cannot re-add element #{inspect(element)}: it was permanently removed"
    end
  end

  def remove(server, element) do
    case GenServer.call(server, {:remove, element}) do
      :ok ->
        :ok

      {:error, :not_a_member} ->
        raise ArgumentError,
              "cannot remove element #{inspect(element)}: not a current member"
    end
  end

  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end

  def members(server) do
    GenServer.call(server, :members)
  end

  def merge(server, %{added: added, removed: removed} = _remote_state) do
    GenServer.call(server, {:merge, %{added: MapSet.new(added), removed: MapSet.new(removed)}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :added and :removed keys, got: #{inspect(invalid)}"
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
  def handle_call({:add, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(removed, element) do
      {:reply, {:error, :tombstoned}, state}
    else
      {:reply, :ok, %{state | added: MapSet.put(added, element)}}
    end
  end

  def handle_call({:remove, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(added, element) and not MapSet.member?(removed, element) do
      {:reply, :ok, %{state | removed: MapSet.put(removed, element)}}
    else
      {:reply, {:error, :not_a_member}, state}
    end
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

  defp empty_state, do: %{added: MapSet.new(), removed: MapSet.new()}

  defp element_present?(%{added: added, removed: removed}, element) do
    MapSet.member?(added, element) and not MapSet.member?(removed, element)
  end

  defp compute_members(%{added: added, removed: removed}) do
    MapSet.difference(added, removed)
  end

  defp merge_states(%{added: la, removed: lr}, %{added: ra, removed: rr}) do
    %{
      added: MapSet.union(la, ra),
      removed: MapSet.union(lr, rr)
    }
  end
end
```
