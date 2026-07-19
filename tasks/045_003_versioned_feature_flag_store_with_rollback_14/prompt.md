# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `hist_table` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `hist_table` missing

```elixir
defmodule FeatureFlags do
  @moduledoc """
  Feature flags with an append-only audit log and rollback.

  Two ETS tables back the store:

  - a `:set` table mapping `flag -> {flag, state, version}` for the current
    state (read directly, no GenServer round-trip), and
  - an `:ordered_set` table mapping `{flag, version} -> state` for the full
    history.

  Every write bumps the flag's version and appends to history. `rollback/1`
  is itself a write: it appends the previous state as a new version.
  """

  use GenServer

  @default_table :feature_flags
  @default_name __MODULE__

  @pt_server {__MODULE__, :server}
  @pt_state {__MODULE__, :state_table}
  @pt_hist {__MODULE__, :hist_table}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the feature-flag server.

  Options:

  - `:table_name` — name of the primary ETS table (default `#{@default_table}`).
  - `:name` — process registration name (default `#{inspect(@default_name)}`);
    pass `nil` to skip registration.

  A second `:ordered_set` history table named `"<table_name>_history"` is also
  created and owned by the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end

  @doc """
  Turns `flag` fully on, recording a new version. Returns `:ok`.
  """
  @spec enable(atom()) :: :ok
  def enable(flag), do: GenServer.call(server(), {:write, flag, {:on}})

  @doc """
  Turns `flag` fully off, recording a new version. Returns `:ok`.
  """
  @spec disable(atom()) :: :ok
  def disable(flag), do: GenServer.call(server(), {:write, flag, {:off}})

  @doc """
  Puts `flag` into `:percentage` mode with `pct` (an integer 0–100),
  recording a new version. Returns `:ok`.
  """
  @spec enable_for_percentage(atom(), 0..100) :: :ok
  def enable_for_percentage(flag, pct)
      when is_integer(pct) and pct >= 0 and pct <= 100 do
    GenServer.call(server(), {:write, flag, {:percentage, pct}})
  end

  @doc """
  Reverts `flag` to its immediately preceding state by appending that state as
  a new version (history keeps growing).

  Returns `:ok` on success, `{:error, :no_previous_version}` when the flag has
  only one version, and `{:error, :unknown_flag}` when it was never set.
  """
  @spec rollback(atom()) :: :ok | {:error, :no_previous_version | :unknown_flag}
  def rollback(flag), do: GenServer.call(server(), {:rollback, flag})

  @doc """
  Returns `true` only when `flag`'s current state is `:on`. Unknown flags and
  flags in any other mode return `false`.
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(flag) do
    case current_state(flag) do
      {:on} -> true
      _ -> false
    end
  end

  @doc """
  Returns `true` when `flag` is `:on`, or when it is in `:percentage` mode and
  `:erlang.phash2({flag, user_id}, 100) < percentage`. The bucket is
  deterministic per `{flag, user_id}` pair. `:off` and unknown flags return
  `false`.
  """
  @spec enabled_for?(atom(), term()) :: boolean()
  def enabled_for?(flag, user_id) do
    case current_state(flag) do
      {:on} -> true
      {:off} -> false
      {:percentage, pct} -> :erlang.phash2({flag, user_id}, 100) < pct
      nil -> false
    end
  end

  @doc """
  Returns the current integer version of `flag`. The first write yields `1` and
  every subsequent write increments it. Unknown flags return `0`.
  """
  @spec version(atom()) :: non_neg_integer()
  def version(flag) do
    case :ets.lookup(state_table(), flag) do
      [{^flag, _state, v}] -> v
      [] -> 0
    end
  end

  @doc """
  Returns `flag`'s history as a list of `{version, state}` tuples in ascending
  version order, where `state` is `{:on}`, `{:off}`, or `{:percentage, n}`.
  Unknown flags return `[]`.
  """
  @spec history(atom()) :: [{pos_integer(), tuple()}]
  def history(flag) do
    hist_table()
    |> :ets.match_object({{flag, :_}, :_})
    |> Enum.map(fn {{^flag, v}, state} -> {v, state} end)
    |> Enum.sort_by(fn {v, _state} -> v end)
  end

  # ---------------------------------------------------------------------------
  # Private read helpers
  # ---------------------------------------------------------------------------

  defp server, do: :persistent_term.get(@pt_server)
  defp state_table, do: :persistent_term.get(@pt_state, @default_table)

  defp hist_table do
    # TODO
  end

  defp current_state(flag) do
    case :ets.lookup(state_table(), flag) do
      [{^flag, state, _v}] -> state
      [] -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{table_name: table_name}) do
    state_table =
      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])

    hist_name = String.to_atom("#{table_name}_history")

    hist_table =
      :ets.new(hist_name, [:ordered_set, :named_table, :public, read_concurrency: true])

    :persistent_term.put(@pt_server, self())
    :persistent_term.put(@pt_state, state_table)
    :persistent_term.put(@pt_hist, hist_table)

    {:ok, %{state_table: state_table, hist_table: hist_table}}
  end

  @impl true
  def handle_call({:write, flag, new_state}, _from, state) do
    write_version(state, flag, new_state)
    {:reply, :ok, state}
  end

  def handle_call({:rollback, flag}, _from, state) do
    reply =
      case :ets.lookup(state.state_table, flag) do
        [] ->
          {:error, :unknown_flag}

        [{^flag, _cur, v}] when v < 2 ->
          {:error, :no_previous_version}

        [{^flag, _cur, v}] ->
          [{{^flag, _pv}, prev_state}] = :ets.lookup(state.hist_table, {flag, v - 1})
          write_version(state, flag, prev_state)
          :ok
      end

    {:reply, reply, state}
  end

  defp write_version(state, flag, new_state) do
    v =
      case :ets.lookup(state.state_table, flag) do
        [{^flag, _s, cur_v}] -> cur_v
        [] -> 0
      end

    new_v = v + 1
    :ets.insert(state.state_table, {flag, new_state, new_v})
    :ets.insert(state.hist_table, {{flag, new_v}, new_state})
    new_v
  end
end
```

Give me only the complete implementation of `hist_table` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
