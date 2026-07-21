# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

Write me an Elixir module called `FeatureFlags` that manages **multivariate** feature flags (A/B/C-style experiments) using ETS for fast reads, backed by a GenServer for writes.

Unlike a plain on/off flag, a multivariate flag deterministically assigns each user to one of several named **variants** according to a weighted split, so you can run experiments where (say) 50% of users see variant `:a`, 30% see `:b`, and 20% see `:c`.

I need these functions in the public API:

- `FeatureFlags.start_link(opts)` to start the process. It should accept an optional `:table_name` for the ETS table (default `:feature_flags`), and an optional `:name` for process registration (pass `nil` to skip registration). Because every other function in the API is module-level (no server argument), `init/1` must publish the started instance for the module to find: put the server pid under `{FeatureFlags, :server}` and the ETS table under `{FeatureFlags, :table_name}` in `:persistent_term`. Writes route through the published pid and reads through the published table, so the MOST RECENTLY STARTED instance serves the module-level API — regardless of whether it was started with a `:name`, a different `:table_name`, or `name: nil`.
- `FeatureFlags.enable(flag_name)` — sets the flag globally on (`:on`).
- `FeatureFlags.disable(flag_name)` — sets the flag globally off (`:off`).
- `FeatureFlags.set_variants(flag_name, variants)` — puts the flag into multivariate mode. `variants` is a list of `{variant_name, weight}` tuples, where `variant_name` is an atom and `weight` is a non-negative integer. Raise an `ArgumentError` if the weights do not sum to exactly `100` (an empty list sums to `0` and is therefore rejected), or if any weight is negative — even when the remaining weights would otherwise total `100`. When `set_variants` raises, the flag is left unchanged: a flag that was never set stays unknown, so `variant_for/2` returns `:off` and `enabled_for?/2` returns `false` for it. A variant with weight `0` receives no users.
- `FeatureFlags.enabled?(flag_name)` — returns `true` only when the flag is globally `:on`. Variant flags and `:off`/unknown flags return `false`.
- `FeatureFlags.variant_for(flag_name, user_id)` — returns the atom the user is assigned to:
  - `:on` flags return `:on`.
  - `:off` and unknown flags return `:off`.
  - variant flags return the assigned variant atom. The assignment must be **deterministic**: the same `{flag_name, user_id}` pair always yields the same variant. Compute `bucket = :erlang.phash2({flag_name, user_id}, 100)` (a 0–99 value) and walk the variants in the order given, accumulating weights, returning the variant whose cumulative range contains the bucket (variant 1 owns `0..w1-1`, variant 2 owns `w1..w1+w2-1`, etc.). Each range is inclusive of its lower cumulative bound and exclusive of its upper one, so a variant with weight `0` (including a leading one) owns no bucket at all.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` when `variant_for/2` is anything other than `:off`.

Note that `enable`, `disable`, and `set_variants` each overwrite whatever state the flag was previously in, so a flag can move freely between `:on`, `:off`, and variant modes.

Implementation requirements:
- ETS table should be of type `:set`, with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly (for `enabled?`, `variant_for`, `enabled_for?`) without going through the GenServer.
- All writes (`enable`, `disable`, `set_variants`) must go through the GenServer via `call` to serialise updates.
- The ETS table must be created in `init/1`.

Give me the complete module in a single file. Use only the OTP standard library, no external dependencies.
