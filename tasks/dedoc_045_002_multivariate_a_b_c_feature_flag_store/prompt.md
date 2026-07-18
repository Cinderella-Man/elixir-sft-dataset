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

  def enable(flag_name), do: GenServer.call(server(), {:set, flag_name, {:on}})

  def disable(flag_name), do: GenServer.call(server(), {:set, flag_name, {:off}})

  def set_variants(flag_name, variants) when is_list(variants) do
    validated = validate_variants(variants)
    GenServer.call(server(), {:set, flag_name, {:variants, validated}})
  end

  def enabled?(flag_name) do
    case lookup(flag_name) do
      {:on} -> true
      _ -> false
    end
  end

  def variant_for(flag_name, user_id) do
    case lookup(flag_name) do
      {:on} -> :on
      {:off} -> :off
      {:variants, variants} -> pick_variant(flag_name, user_id, variants)
      nil -> :off
    end
  end

  def enabled_for?(flag_name, user_id), do: variant_for(flag_name, user_id) != :off

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp validate_variants(variants) do
    Enum.each(variants, fn
      {name, weight} when is_atom(name) and is_integer(weight) and weight >= 0 ->
        :ok

      other ->
        raise ArgumentError, "invalid variant spec: #{inspect(other)}"
    end)

    total = Enum.reduce(variants, 0, fn {_name, weight}, acc -> acc + weight end)

    unless total == 100 do
      raise ArgumentError, "variant weights must sum to 100, got #{total}"
    end

    variants
  end

  defp pick_variant(flag_name, user_id, variants) do
    bucket = :erlang.phash2({flag_name, user_id}, 100)
    select(variants, bucket, 0)
  end

  defp select([{name, weight} | rest], bucket, acc) do
    upper = acc + weight
    if bucket < upper, do: name, else: select(rest, bucket, upper)
  end

  defp select([], _bucket, _acc), do: :off

  defp server, do: :persistent_term.get(@pt_server)

  defp lookup(flag_name) do
    table = :persistent_term.get(@pt_table, @default_table)

    case :ets.lookup(table, flag_name) do
      [{^flag_name, value}] -> value
      [] -> nil
    end
  end

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
  def handle_call({:set, flag_name, value}, _from, %{table: table} = state) do
    :ets.insert(table, {flag_name, value})
    {:reply, :ok, state}
  end
end
```
