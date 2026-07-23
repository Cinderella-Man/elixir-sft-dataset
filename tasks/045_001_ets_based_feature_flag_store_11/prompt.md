# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

**Summary:** Implement `FeatureFlags` — an Elixir module for feature-flag management with ETS-backed fast reads and a GenServer serialising writes. Single file, OTP standard library only, no external dependencies.

**Startup — `FeatureFlags.start_link(opts)`**
- Starts the process.
- Accepts optional `:table_name` for the ETS table; default `:feature_flags`.
- Accepts optional `:name` for process registration; default `FeatureFlags`. Pass `nil` to skip registration.
- Every other function in the API is module-level (no server argument), so `init/1` must publish the started instance for the module to find: put the server pid under `{FeatureFlags, :server}` and the ETS table name under `{FeatureFlags, :table_name}` in `:persistent_term`.
- Writes route through the published pid; reads route through the published table.
- Reads fall back to `:feature_flags` when nothing has been published yet.
- Consequence: the MOST RECENTLY STARTED instance serves the module-level API, regardless of which `:name` or `:table_name` it was started with.

**Writes**
- `FeatureFlags.enable(flag_name)` — sets the flag to `:on` for everyone. Returns `:ok`.
- `FeatureFlags.disable(flag_name)` — sets the flag to `:off` for everyone. Returns `:ok`.
- `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets the flag to `:percentage` mode with an integer value between `0` and `100`. Returns `:ok`.
- `0` is equivalent to `:off`; `100` is equivalent to `:on`.
- Guard `percentage`: a non-integer or out-of-range value raises `FunctionClauseError` and stores nothing (the flag stays unknown).
- All writes (`enable`, `disable`, `enable_for_percentage`) go through the GenServer via `call` to serialise updates.

**Reads**
- `FeatureFlags.enabled?(flag_name)` — `true` if the flag is `:on`, `false` otherwise (`:off` and `:percentage` flags return `false` here). Unknown flags default to `false`.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — `true` if the flag is `:on`, or if the flag is in `:percentage` mode and the user falls within the enabled bucket.
- Bucketing must be **deterministic**: the same `{flag_name, user_id}` pair always produces the same result across calls.
- Compute the 0–99 hash with `:erlang.phash2({flag_name, user_id}, 100)`; the user is in the bucket when that hash is **strictly less than** the percentage (a hash exactly equal to the percentage is excluded).
- If the flag is `:off`, always return `false`. Unknown flags default to `false`.

**ETS table**
- Type `:set`, `read_concurrency: true`, owned by the GenServer.
- Named, so any process can read directly without going through the GenServer process for `enabled?` and `enabled_for?` reads.
- Created in `init/1`; the table name accessible via a module attribute or passed through the GenServer state.

**Deliverable**
- The complete module in a single file.

## The module with `start_link` missing

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

  def start_link(opts \\ []) do
    # TODO
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

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
