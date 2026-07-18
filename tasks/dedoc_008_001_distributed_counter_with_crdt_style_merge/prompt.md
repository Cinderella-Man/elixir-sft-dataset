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
defmodule Counter do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {name_opts, _rest} =
      Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  def increment(server, node_id, amount \\ 1) do
    validate_amount!(amount, :increment)
    GenServer.call(server, {:increment, node_id, amount})
  end

  def decrement(server, node_id, amount \\ 1) do
    validate_amount!(amount, :decrement)
    GenServer.call(server, {:decrement, node_id, amount})
  end

  def value(server) do
    GenServer.call(server, :value)
  end

  def merge(server, %{p: p, n: n} = _remote_state)
      when is_map(p) and is_map(n) do
    GenServer.call(server, {:merge, %{p: p, n: n}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :p and :n keys, got: #{inspect(invalid)}"
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
  def handle_call({:increment, node_id, amount}, _from, state) do
    new_state = update_in(state, [:p, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call({:decrement, node_id, amount}, _from, state) do
    new_state = update_in(state, [:n, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call(:value, _from, state) do
    {:reply, compute_value(state), state}
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

  defp empty_state, do: %{p: %{}, n: %{}}

  defp compute_value(%{p: p, n: n}) do
    sum_map(p) - sum_map(n)
  end

  defp sum_map(map), do: Enum.reduce(map, 0, fn {_k, v}, acc -> acc + v end)

  defp merge_states(%{p: lp, n: ln}, %{p: rp, n: rn}) do
    %{
      p: merge_g_counters(lp, rp),
      n: merge_g_counters(ln, rn)
    }
  end

  # Merges two G-Counters by taking the per-node maximum.
  defp merge_g_counters(local, remote) do
    Map.merge(local, remote, fn _node_id, l_val, r_val -> max(l_val, r_val) end)
  end

  defp validate_amount!(amount, _op) when is_integer(amount) and amount > 0, do: :ok

  defp validate_amount!(amount, op) do
    raise ArgumentError,
          "amount for #{op} must be a positive integer, got: #{inspect(amount)}"
  end
end
```
