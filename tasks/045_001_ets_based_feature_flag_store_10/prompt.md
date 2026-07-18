# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `FeatureFlags` that manages feature flags using ETS for fast reads, backed by a GenServer for writes.

I need these functions in the public API:

- `FeatureFlags.start_link(opts)` to start the process. It should accept an optional `:table_name` for the ETS table (default `:feature_flags`), and an optional `:name` for process registration.
- `FeatureFlags.enable(flag_name)` — sets the flag to `:on` for everyone. Returns `:ok`.
- `FeatureFlags.disable(flag_name)` — sets the flag to `:off` for everyone. Returns `:ok`.
- `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets the flag to `:percentage` mode with a value between `0` and `100` (integers). Returns `:ok`. Calling with `0` is equivalent to `:off`, and `100` is equivalent to `:on`. Guard the argument so a non-integer or out-of-range `percentage` raises `FunctionClauseError` and stores nothing (the flag stays unknown).
- `FeatureFlags.enabled?(flag_name)` — returns `true` if the flag is `:on`, `false` otherwise (`:off` or `:percentage` flags return `false` here). Unknown flags default to `false`.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` if the flag is `:on`, or if the flag is in `:percentage` mode and the user falls within the enabled bucket. The bucket must be **deterministic**: the same `{flag_name, user_id}` pair must always produce the same result across calls. Use `:erlang.phash2({flag_name, user_id}, 100)` to compute a 0–99 hash; the user is in the bucket when that hash is **strictly less than** the percentage (so a hash exactly equal to the percentage is excluded). If the flag is `:off`, always return `false`. Unknown flags default to `false`.

Implementation requirements:
- ETS table should be of type `:set`, with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly without going through the GenServer process for `enabled?` and `enabled_for?` reads.
- All writes (`enable`, `disable`, `enable_for_percentage`) must go through the GenServer via `call` to serialise updates.
- The ETS table must be created in `init/1` and the table name should be accessible via a module attribute or passed through the GenServer state.

Give me the complete module in a single file. Use only the OTP standard library, no external dependencies.

## The module with `handle_call` missing

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

  def handle_call({:set, flag_name, value}, _from, %{table: table} = state) do
    # TODO
  end
end
```

Give me only the complete implementation of `handle_call` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
