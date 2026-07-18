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
defmodule FeatureFlags do
  use GenServer

  @default_table :feature_flags
  @default_name __MODULE__

  @pt_server {__MODULE__, :server}
  @pt_state {__MODULE__, :state_table}
  @pt_hist {__MODULE__, :hist_table}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end

  def enable(flag), do: GenServer.call(server(), {:write, flag, {:on}})

  def disable(flag), do: GenServer.call(server(), {:write, flag, {:off}})

  def enable_for_percentage(flag, pct)
      when is_integer(pct) and pct >= 0 and pct <= 100 do
    GenServer.call(server(), {:write, flag, {:percentage, pct}})
  end

  def rollback(flag), do: GenServer.call(server(), {:rollback, flag})

  def enabled?(flag) do
    case current_state(flag) do
      {:on} -> true
      _ -> false
    end
  end

  def enabled_for?(flag, user_id) do
    case current_state(flag) do
      {:on} -> true
      {:off} -> false
      {:percentage, pct} -> :erlang.phash2({flag, user_id}, 100) < pct
      nil -> false
    end
  end

  def version(flag) do
    case :ets.lookup(state_table(), flag) do
      [{^flag, _state, v}] -> v
      [] -> 0
    end
  end

  def history(flag) do
    hist_table()
    |> :ets.match_object({{flag, :_}, :_})
    |> Enum.map(fn {{^flag, v}, state} -> {v, state} end)
    |> Enum.sort_by(fn {v, _state} -> v end)
  end

  # ---------------------------------------------------------------------------
  # Private read helpers
  # ---------------------------------------------------------------------------

  defp server, do: :persistent_term.get(@pt_server)
  defp state_table, do: :persistent_term.get(@pt_state, @default_table)
  defp hist_table, do: :persistent_term.get(@pt_hist)

  defp current_state(flag) do
    case :ets.lookup(state_table(), flag) do
      [{^flag, state, _v}] -> state
      [] -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{table_name: table_name}) do
    state_table =
      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])

    hist_name = String.to_atom("#{table_name}_history")

    hist_table =
      :ets.new(hist_name, [:ordered_set, :named_table, :public, read_concurrency: true])

    :persistent_term.put(@pt_server, self())
    :persistent_term.put(@pt_state, state_table)
    :persistent_term.put(@pt_hist, hist_table)

    {:ok, %{state_table: state_table, hist_table: hist_table}}
  end

  @impl true
  def handle_call({:write, flag, new_state}, _from, state) do
    write_version(state, flag, new_state)
    {:reply, :ok, state}
  end

  def handle_call({:rollback, flag}, _from, state) do
    reply =
      case :ets.lookup(state.state_table, flag) do
        [] ->
          {:error, :unknown_flag}

        [{^flag, _cur, v}] when v < 2 ->
          {:error, :no_previous_version}

        [{^flag, _cur, v}] ->
          [{{^flag, _pv}, prev_state}] = :ets.lookup(state.hist_table, {flag, v - 1})
          write_version(state, flag, prev_state)
          :ok
      end

    {:reply, reply, state}
  end

  defp write_version(state, flag, new_state) do
    v =
      case :ets.lookup(state.state_table, flag) do
        [{^flag, _s, cur_v}] -> cur_v
        [] -> 0
      end

    new_v = v + 1
    :ets.insert(state.state_table, {flag, new_state, new_v})
    :ets.insert(state.hist_table, {{flag, new_v}, new_state})
    new_v
  end
end
```
