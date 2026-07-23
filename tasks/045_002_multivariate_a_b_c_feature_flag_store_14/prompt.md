# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Hey — I need you to write a module for us called `FeatureFlags`. It's a **multivariate** feature flag store (A/B/C-style experiments), reading out of ETS so lookups are fast, with a GenServer sitting behind it to handle the writes.

The thing that makes it different from a plain on/off flag is that a multivariate flag deterministically assigns each user to one of several named **variants** according to a weighted split, so we can run experiments where (say) 50% of users see variant `:a`, 30% see `:b`, and 20% see `:c`.

Here's the public API I'm after:

- `FeatureFlags.start_link(opts)` to start the process. I want it to accept an optional `:table_name` for the ETS table (defaulting to `:feature_flags`), and an optional `:name` for process registration (passing `nil` should skip registration entirely). Since every other function in the API is module-level and takes no server argument, `init/1` has to publish the started instance somewhere the module can find it: stash the server pid under `{FeatureFlags, :server}` and the ETS table under `{FeatureFlags, :table_name}` in `:persistent_term`. Writes then route through the published pid and reads through the published table, which means the MOST RECENTLY STARTED instance is the one serving the module-level API — doesn't matter whether it was started with a `:name`, with a different `:table_name`, or with `name: nil`.
- `FeatureFlags.enable(flag_name)` — turns the flag globally on (`:on`).
- `FeatureFlags.disable(flag_name)` — turns the flag globally off (`:off`).
- `FeatureFlags.set_variants(flag_name, variants)` — flips the flag into multivariate mode. `variants` comes in as a list of `{variant_name, weight}` tuples, where `variant_name` is an atom and `weight` is a non-negative integer. I want it to raise an `ArgumentError` if the weights don't sum to exactly `100` (an empty list sums to `0`, so that gets rejected too), or if any weight is negative — and yes, still raise in the negative case even when the remaining weights would otherwise add up to `100`. Important: when `set_variants` raises, the flag must be left exactly as it was, so a flag that was never set stays unknown and `variant_for/2` returns `:off` and `enabled_for?/2` returns `false` for it. And a variant with weight `0` should receive no users.
- `FeatureFlags.enabled?(flag_name)` — `true` only when the flag is globally `:on`. Variant flags, `:off` flags, and unknown flags all come back `false`.
- `FeatureFlags.variant_for(flag_name, user_id)` — gives back the atom the user landed on. `:on` flags return `:on`. `:off` flags and unknown flags return `:off`. Variant flags return the assigned variant atom, and that assignment has to be **deterministic** — the same `{flag_name, user_id}` pair always yields the same variant. Compute `bucket = :erlang.phash2({flag_name, user_id}, 100)` (so a 0–99 value), then walk the variants in the order they were given, accumulating weights, and return the variant whose cumulative range contains the bucket: variant 1 owns `0..w1-1`, variant 2 owns `w1..w1+w2-1`, and so on. Each range is inclusive of its lower cumulative bound and exclusive of its upper one, which is what makes a variant with weight `0` (including a leading one) own no bucket at all.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — `true` whenever `variant_for/2` is anything other than `:off`.

One more behavioral note: `enable`, `disable`, and `set_variants` each overwrite whatever state the flag was previously in, so a flag can move freely between `:on`, `:off`, and variant modes.

On the implementation side, a few things I care about. The ETS table should be type `:set`, with `read_concurrency: true`, owned by the GenServer, and named so that any process can read it directly for `enabled?`, `variant_for`, and `enabled_for?` without going through the GenServer at all. All the writes (`enable`, `disable`, `set_variants`) must go through the GenServer via `call` so updates are serialised. And the ETS table has to be created in `init/1`.

Give me the complete module in a single file, please. OTP standard library only, no external dependencies.

## The module with `init` missing

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

  def init(%{table_name: table_name}) do
    # TODO
  end

  @impl true
  def handle_call({:set, flag_name, value}, _from, %{table: table} = state) do
    :ets.insert(table, {flag_name, value})
    {:reply, :ok, state}
  end
end
```

Give me only the complete implementation of `init` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
