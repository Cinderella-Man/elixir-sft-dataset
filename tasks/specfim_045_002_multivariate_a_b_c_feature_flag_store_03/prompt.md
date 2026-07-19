# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`enable/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `enable/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `enable/1` missing

```elixir
defmodule FeatureFlags do
  @moduledoc """
  Multivariate (A/B/C) feature flags backed by ETS for concurrent reads and a
  GenServer for serialised writes.

  A flag is in one of three states:

  - `{:on}`  — globally enabled; every user is assigned `:on`.
  - `{:off}` — globally disabled; every user is assigned `:off`.
  - `{:variants, [{name, weight}, ...]}` — users are deterministically split
    across variants by weight. `:erlang.phash2({flag, user}, 100)` yields a
    0–99 bucket which is matched against the cumulative weight ranges.
  """

  use GenServer

  @default_table :feature_flags
  @default_name __MODULE__

  @pt_server {__MODULE__, :server}
  @pt_table {__MODULE__, :table_name}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end

  @doc "Enables `flag_name` globally (`:on`)."
  # TODO: @spec
  def enable(flag_name), do: GenServer.call(server(), {:set, flag_name, {:on}})

  @doc "Disables `flag_name` globally (`:off`)."
  @spec disable(atom()) :: :ok
  def disable(flag_name), do: GenServer.call(server(), {:set, flag_name, {:off}})

  @doc """
  Puts `flag_name` into multivariate mode.

  `variants` is a list of `{variant_atom, weight_integer}` tuples whose weights
  must sum to exactly 100. Raises `ArgumentError` otherwise.
  """
  @spec set_variants(atom(), [{atom(), non_neg_integer()}]) :: :ok
  def set_variants(flag_name, variants) when is_list(variants) do
    validated = validate_variants(variants)
    GenServer.call(server(), {:set, flag_name, {:variants, validated}})
  end

  @doc "Returns `true` only when `flag_name` is globally `:on`."
  @spec enabled?(atom()) :: boolean()
  def enabled?(flag_name) do
    case lookup(flag_name) do
      {:on} -> true
      _ -> false
    end
  end

  @doc """
  Returns the variant `user_id` is assigned to for `flag_name`.

  `:on` flags return `:on`; `:off`/unknown flags return `:off`; variant flags
  return the deterministically assigned variant atom.
  """
  @spec variant_for(atom(), term()) :: atom()
  def variant_for(flag_name, user_id) do
    case lookup(flag_name) do
      {:on} -> :on
      {:off} -> :off
      {:variants, variants} -> pick_variant(flag_name, user_id, variants)
      nil -> :off
    end
  end

  @doc "Returns `true` when `variant_for/2` is anything other than `:off`."
  @spec enabled_for?(atom(), term()) :: boolean()
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
