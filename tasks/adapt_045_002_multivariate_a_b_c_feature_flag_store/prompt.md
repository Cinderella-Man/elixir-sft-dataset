# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule FeatureFlags do
  @moduledoc """
  Manages feature flags using ETS for fast, concurrent reads and a GenServer
  for serialised writes.

  ## Flag states

  Each flag can be in one of three states:

  - `{:on}` — enabled for everyone.
  - `{:off}` — disabled for everyone.
  - `{:percentage, n}` — enabled for the `n`% of users whose
    `:erlang.phash2({flag_name, user_id}, 100)` hash falls below `n`.

  ## Usage

      {:ok, _pid} = FeatureFlags.start_link([])

      FeatureFlags.enable(:dark_mode)
      FeatureFlags.enabled?(:dark_mode)            #=> true
      FeatureFlags.enabled_for?(:dark_mode, "u1")  #=> true

      FeatureFlags.enable_for_percentage(:beta, 30)
      FeatureFlags.enabled?(:beta)                 #=> false  (not globally on)
      FeatureFlags.enabled_for?(:beta, "u1")       #=> deterministic true/false

      FeatureFlags.disable(:dark_mode)
      FeatureFlags.enabled?(:dark_mode)            #=> false
  """

  use GenServer

  @default_table :feature_flags
  @default_name __MODULE__

  @pt_server {__MODULE__, :server}
  @pt_table {__MODULE__, :table_name}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `FeatureFlags` GenServer and creates the backing ETS table.

  ## Options

  - `:table_name` – atom used as the ETS table name (default: `:feature_flags`).
  - `:name`       – name used to register the GenServer process
                    (default: `FeatureFlags`). Pass `nil` to skip registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)

    # Only forward the :name option when a non-nil name is requested;
    # passing `name: nil` to GenServer.start_link/3 is not valid.
    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end

  @doc "Enables `flag_name` for **all** users (`:on` state)."
  @spec enable(atom()) :: :ok
  def enable(flag_name) do
    GenServer.call(server(), {:set, flag_name, {:on}})
  end

  @doc "Disables `flag_name` for **all** users (`:off` state)."
  @spec disable(atom()) :: :ok
  def disable(flag_name) do
    GenServer.call(server(), {:set, flag_name, {:off}})
  end

  @doc """
  Enables `flag_name` for `percentage`% of users (0–100).

  The bucket assignment is deterministic per `{flag_name, user_id}` pair.
  Passing `0` is equivalent to `disable/1`; passing `100` is equivalent
  to `enable/1`.
  """
  @spec enable_for_percentage(atom(), 0..100) :: :ok
  def enable_for_percentage(flag_name, percentage)
      when is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(server(), {:set, flag_name, {:percentage, percentage}})
  end

  @doc """
  Returns `true` only when `flag_name` is in the `:on` state.

  Reads directly from ETS — no GenServer round-trip.
  Unknown flags return `false`.
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(flag_name) do
    case lookup(flag_name) do
      {:on} -> true
      _ -> false
    end
  end

  @doc """
  Returns `true` when:

  - the flag is `:on`, **or**
  - the flag is in `:percentage` mode and
    `phash2({flag_name, user_id}, 100) < percentage`.

  Reads directly from ETS — no GenServer round-trip.
  Unknown flags return `false`.
  """
  @spec enabled_for?(atom(), term()) :: boolean()
  def enabled_for?(flag_name, user_id) do
    case lookup(flag_name) do
      {:on} -> true
      {:off} -> false
      {:percentage, pct} -> :erlang.phash2({flag_name, user_id}, 100) < pct
      nil -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Returns the GenServer pid stored at startup — works whether the server
  # was registered by name or started anonymously.
  defp server, do: :persistent_term.get(@pt_server)

  # Reads the flag value directly from ETS in the calling process.
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

  @impl GenServer
  def init(%{table_name: table_name}) do
    table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true
      ])

    # Publish both the pid and the table name so the public functions can
    # reach them without a GenServer call, regardless of registration name.
    :persistent_term.put(@pt_server, self())
    :persistent_term.put(@pt_table, table)

    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:set, flag_name, value}, _from, %{table: table} = state) do
    :ets.insert(table, {flag_name, value})
    {:reply, :ok, state}
  end
end
```

## New specification

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
