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

Write me an Elixir module called `FeatureFlags` that manages feature flags using ETS for fast reads, backed by a GenServer for writes, with **full change history and rollback** (an audit log).

Every write records a new immutable version, so you can inspect how a flag evolved and revert it.

I need these functions in the public API:

- `FeatureFlags.start_link(opts)` to start the process. It should accept an optional `:table_name` for the primary ETS table (default `:feature_flags`), and an optional `:name` for process registration (pass `nil` to skip registration). You may create a second ETS table for history (e.g. named after `table_name`).
- `FeatureFlags.enable(flag_name)` — sets the flag to `:on`.
- `FeatureFlags.disable(flag_name)` — sets the flag to `:off`.
- `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets `:percentage` mode with an integer 0–100.
- `FeatureFlags.enabled?(flag_name)` — returns `true` only when the flag is `:on`. Unknown flags default to `false`.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` if the flag is `:on`, or if it is in `:percentage` mode and `:erlang.phash2({flag_name, user_id}, 100) < percentage`. `:off` and unknown flags return `false`. The bucket must be deterministic per `{flag_name, user_id}` pair.
- `FeatureFlags.version(flag_name)` — returns the current integer version. The first write produces version `1`; every subsequent write increments it. Unknown flags return `0`.
- `FeatureFlags.history(flag_name)` — returns a list of `{version, state}` tuples in **ascending version order**, where `state` is `{:on}`, `{:off}`, or `{:percentage, n}`. Unknown flags return `[]`.
- `FeatureFlags.rollback(flag_name)` — reverts the flag to its **immediately preceding** state. Rollback is append-only: it writes the previous state as a brand-new version (so the history grows). Returns `:ok` on success, `{:error, :no_previous_version}` if the flag has only one version, and `{:error, :unknown_flag}` if the flag was never set.

Implementation requirements:
- The primary ETS table should be of type `:set` with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly (for `enabled?`, `enabled_for?`, `version`, `history`) without a GenServer round-trip.
- All state-changing operations (`enable`, `disable`, `enable_for_percentage`, `rollback`) must go through the GenServer via `call` to serialise updates and keep version numbers consistent.
- ETS tables must be created in `init/1`.

Give me the complete module in a single file. Use only the OTP standard library, no external dependencies.
