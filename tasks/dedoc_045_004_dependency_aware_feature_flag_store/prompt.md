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
  @pt_table {__MODULE__, :table_name}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end

  def enable(flag), do: GenServer.call(server(), {:set_state, flag, {:on}})

  def disable(flag), do: GenServer.call(server(), {:set_state, flag, {:off}})

  def enable_for_percentage(flag, pct)
      when is_integer(pct) and pct >= 0 and pct <= 100 do
    GenServer.call(server(), {:set_state, flag, {:percentage, pct}})
  end

  def set_prerequisites(flag, prereqs) when is_list(prereqs) do
    GenServer.call(server(), {:set_prereqs, flag, prereqs})
  end

  def prerequisites(flag) do
    case record(flag) do
      nil -> []
      {_state, prereqs} -> prereqs
    end
  end

  def enabled?(flag) do
    case record(flag) do
      nil -> false
      {state, prereqs} -> state_on?(state) and Enum.all?(prereqs, &enabled?/1)
    end
  end

  def enabled_for?(flag, user_id) do
    case record(flag) do
      nil ->
        false

      {state, prereqs} ->
        eval(state, flag, user_id) and Enum.all?(prereqs, &enabled_for?(&1, user_id))
    end
  end

  # ---------------------------------------------------------------------------
  # Private read helpers
  # ---------------------------------------------------------------------------

  defp server, do: :persistent_term.get(@pt_server)
  defp table, do: :persistent_term.get(@pt_table, @default_table)

  defp record(flag) do
    case :ets.lookup(table(), flag) do
      [{^flag, state, prereqs}] -> {state, prereqs}
      [] -> nil
    end
  end

  defp state_on?({:on}), do: true
  defp state_on?(_), do: false

  defp eval({:on}, _flag, _user), do: true
  defp eval({:off}, _flag, _user), do: false
  defp eval({:percentage, pct}, flag, user), do: :erlang.phash2({flag, user}, 100) < pct

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{table_name: table_name}) do
    table =
      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])

    :persistent_term.put(@pt_server, self())
    :persistent_term.put(@pt_table, table)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:set_state, flag, new_state}, _from, %{table: table} = state) do
    prereqs = existing_prereqs(table, flag)
    :ets.insert(table, {flag, new_state, prereqs})
    {:reply, :ok, state}
  end

  def handle_call({:set_prereqs, flag, prereqs}, _from, %{table: table} = state) do
    reply =
      if Enum.any?(prereqs, fn p -> reaches?(table, p, flag, MapSet.new()) end) do
        {:error, :cycle}
      else
        cur_state = existing_state(table, flag)
        :ets.insert(table, {flag, cur_state, prereqs})
        :ok
      end

    {:reply, reply, state}
  end

  defp existing_prereqs(table, flag) do
    case :ets.lookup(table, flag) do
      [{^flag, _s, ps}] -> ps
      [] -> []
    end
  end

  defp existing_state(table, flag) do
    case :ets.lookup(table, flag) do
      [{^flag, s, _ps}] -> s
      [] -> {:off}
    end
  end

  # Would adding edges flag -> prereqs create a cycle? True if any prereq can
  # already reach `flag` through the existing prerequisite graph.
  defp reaches?(table, from, target, visited) do
    cond do
      from == target ->
        true

      MapSet.member?(visited, from) ->
        false

      true ->
        visited = MapSet.put(visited, from)

        Enum.any?(existing_prereqs(table, from), fn n ->
          reaches?(table, n, target, visited)
        end)
    end
  end
end
```
