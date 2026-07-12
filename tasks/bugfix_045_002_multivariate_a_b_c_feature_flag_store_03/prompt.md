# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `FeatureFlags` that manages **multivariate** feature flags (A/B/C-style experiments) using ETS for fast reads, backed by a GenServer for writes.

Unlike a plain on/off flag, a multivariate flag deterministically assigns each user to one of several named **variants** according to a weighted split, so you can run experiments where (say) 50% of users see variant `:a`, 30% see `:b`, and 20% see `:c`.

I need these functions in the public API:

- `FeatureFlags.start_link(opts)` to start the process. It should accept an optional `:table_name` for the ETS table (default `:feature_flags`), and an optional `:name` for process registration (pass `nil` to skip registration).
- `FeatureFlags.enable(flag_name)` — sets the flag globally on (`:on`).
- `FeatureFlags.disable(flag_name)` — sets the flag globally off (`:off`).
- `FeatureFlags.set_variants(flag_name, variants)` — puts the flag into multivariate mode. `variants` is a list of `{variant_name, weight}` tuples, where `variant_name` is an atom and `weight` is a non-negative integer. The weights **must sum to exactly 100**; otherwise raise an `ArgumentError`. A variant with weight `0` receives no users.
- `FeatureFlags.enabled?(flag_name)` — returns `true` only when the flag is globally `:on`. Variant flags and `:off`/unknown flags return `false`.
- `FeatureFlags.variant_for(flag_name, user_id)` — returns the atom the user is assigned to:
  - `:on` flags return `:on`.
  - `:off` and unknown flags return `:off`.
  - variant flags return the assigned variant atom. The assignment must be **deterministic**: the same `{flag_name, user_id}` pair always yields the same variant. Compute `bucket = :erlang.phash2({flag_name, user_id}, 100)` (a 0–99 value) and walk the variants in the order given, accumulating weights, returning the variant whose cumulative range contains the bucket (variant 1 owns `0..w1-1`, variant 2 owns `w1..w1+w2-1`, etc.).
- `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` when `variant_for/2` is anything other than `:off`.

Implementation requirements:
- ETS table should be of type `:set`, with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly (for `enabled?`, `variant_for`, `enabled_for?`) without going through the GenServer.
- All writes (`enable`, `disable`, `set_variants`) must go through the GenServer via `call` to serialise updates.
- The ETS table must be created in `init/1`.

Give me the complete module in a single file. Use only the OTP standard library, no external dependencies.

## The buggy module

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
  @spec enable(atom()) :: :ok
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

    total = Enum.reduce(variants, 1, fn {_name, weight}, acc -> acc + weight end)

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

## Failing test report

```
8 of 12 test(s) failed:

  * test variant flags are not globally enabled?
      variant weights must sum to 100, got 101

  * test assignment is deterministic across calls
      variant weights must sum to 100, got 101

  * test assignment matches the cumulative-bucket formula
      variant weights must sum to 100, got 101

  * test distribution roughly matches weights
      variant weights must sum to 100, got 101

  (…4 more)
```
