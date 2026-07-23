# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Design Brief: `FeatureFlags` — a dependency-aware feature flag store

## Problem

We need a feature flag store for Elixir that serves reads at ETS speed while routing every write through a GenServer, and that supports **prerequisite dependencies** between flags.

A flag can declare that it depends on other flags: it is only considered enabled when all of its prerequisites are also enabled (evaluated transitively). This is useful for gating a feature behind a chain of rollouts.

Deliverable: the complete module, called `FeatureFlags`, in a single file.

## Constraints

- ETS table should be of type `:set` with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly (for `enabled?`, `enabled_for?`, `prerequisites`) — the recursive dependency evaluation happens in the calling process straight against ETS, with no GenServer round-trip.
- All writes (`enable`, `disable`, `enable_for_percentage`, `set_prerequisites`) must go through the GenServer via `call`. Cycle detection must happen in the GenServer before committing prerequisites.
- The ETS table must be created in `init/1`.
- Use only the OTP standard library, no external dependencies.

## Required interface

1. `FeatureFlags.start_link(opts)` — starts the process, returning `{:ok, pid}` on success. It should accept an optional `:table_name` for the ETS table (default `:feature_flags`), and an optional `:name` for process registration (pass `nil` to skip registration). The write functions below take no server argument, so they must still reach the running process even when it is started with `name: nil` (i.e. unregistered) — track the running instance globally.
2. `FeatureFlags.enable(flag_name)` — sets the flag's own state to `:on`.
3. `FeatureFlags.disable(flag_name)` — sets the flag's own state to `:off`.
4. `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets the flag's own state to `:percentage` mode with an integer 0–100.
5. `FeatureFlags.set_prerequisites(flag_name, prereqs)` — declares that `flag_name` requires every flag in the list `prereqs` (a list of atoms). Setting prerequisites must **not** create a cycle (including self-dependency or a transitive loop through existing prerequisites); if it would, leave the graph unchanged and return `{:error, :cycle}`. Otherwise return `:ok`. Setting prerequisites preserves the flag's own state, and setting state preserves prerequisites.
6. `FeatureFlags.prerequisites(flag_name)` — returns the flag's declared prerequisite list (or `[]`).
7. `FeatureFlags.enabled?(flag_name)` — returns `true` only when the flag's own state is `:on` **and** every prerequisite is `enabled?` (recursively). Unknown flags default to `false`.
8. `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` when the flag's own state evaluates true for that user (`:on`, or `:percentage` mode with `:erlang.phash2({flag_name, user_id}, 100) < percentage`) **and** every prerequisite is `enabled_for?/2` for the same `user_id` (recursively). `:off` and unknown flags return `false`. The bucket must be deterministic per `{flag_name, user_id}` pair.

## Acceptance criteria

- All eight public functions above exist with the stated arities and return values.
- Enabling/disabling and percentage rollout are settable independently of prerequisites, and neither operation clobbers the other.
- Cycle-creating calls to `set_prerequisites/2` return `{:error, :cycle}` and leave the prerequisite graph untouched; all other calls return `:ok`.
- `enabled?/1` and `enabled_for?/2` resolve prerequisite chains transitively and return `false` for unknown flags.
- Repeated `enabled_for?/2` calls for the same `{flag_name, user_id}` pair yield the same result.
- Reads hit the named ETS table directly from the caller; writes are GenServer `call`s.
- Works when started with `name: nil`.

## The module with `handle_call` missing

```elixir
defmodule FeatureFlags do
  @moduledoc """
  Feature flags with prerequisite dependencies, backed by ETS for concurrent
  reads and a GenServer for serialised writes.

  Each flag is stored as `{flag, state, prereqs}` where `state` is `{:on}`,
  `{:off}`, or `{:percentage, n}`, and `prereqs` is a list of atoms. A flag is
  only enabled when its own state evaluates true AND every prerequisite is
  (recursively) enabled. `set_prerequisites/2` rejects edges that would create
  a cycle.
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
  Starts the feature-flag process.

  Options:

    * `:table_name` — name of the ETS table (default `#{inspect(@default_table)}`);
    * `:name` — process registration name; pass `nil` to skip registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end

  @doc """
  Sets the flag's own state to `:on`, preserving its prerequisites.
  """
  @spec enable(atom()) :: :ok
  def enable(flag), do: GenServer.call(server(), {:set_state, flag, {:on}})

  @doc """
  Sets the flag's own state to `:off`, preserving its prerequisites.
  """
  @spec disable(atom()) :: :ok
  def disable(flag), do: GenServer.call(server(), {:set_state, flag, {:off}})

  @doc """
  Sets the flag's own state to percentage rollout mode with `pct` (0–100),
  preserving its prerequisites.
  """
  @spec enable_for_percentage(atom(), 0..100) :: :ok
  def enable_for_percentage(flag, pct)
      when is_integer(pct) and pct >= 0 and pct <= 100 do
    GenServer.call(server(), {:set_state, flag, {:percentage, pct}})
  end

  @doc """
  Declares that `flag` requires every flag in `prereqs`.

  Returns `{:error, :cycle}` (leaving the graph unchanged) if the edges would
  create a cycle — including self-dependency or a transitive loop — otherwise
  `:ok`. The flag's own state is preserved.
  """
  @spec set_prerequisites(atom(), [atom()]) :: :ok | {:error, :cycle}
  def set_prerequisites(flag, prereqs) when is_list(prereqs) do
    GenServer.call(server(), {:set_prereqs, flag, prereqs})
  end

  @doc """
  Returns the flag's declared prerequisite list, or `[]` for unknown flags.
  """
  @spec prerequisites(atom()) :: [atom()]
  def prerequisites(flag) do
    case record(flag) do
      nil -> []
      {_state, prereqs} -> prereqs
    end
  end

  @doc """
  Returns `true` only when the flag's own state is `:on` and every prerequisite
  is (recursively) enabled. Unknown flags return `false`.
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(flag) do
    case record(flag) do
      nil -> false
      {state, prereqs} -> state_on?(state) and Enum.all?(prereqs, &enabled?/1)
    end
  end

  @doc """
  Returns `true` when the flag's own state evaluates true for `user_id` and
  every prerequisite is (recursively) enabled for the same `user_id`.

  For percentage mode the user is bucketed via
  `:erlang.phash2({flag, user_id}, 100)`. `:off` and unknown flags return
  `false`.
  """
  @spec enabled_for?(atom(), term()) :: boolean()
  def enabled_for?(flag, user_id) do
    case record(flag) do
      nil ->
        false

      {state, prereqs} ->
        eval(state, flag, user_id) and Enum.all?(prereqs, &enabled_for?(&1, user_id))
    end
  end

  # ---------------------------------------------------------------------------
  # Private read helpers
  # ---------------------------------------------------------------------------

  defp server, do: :persistent_term.get(@pt_server)
  defp table, do: :persistent_term.get(@pt_table, @default_table)

  defp record(flag) do
    case :ets.lookup(table(), flag) do
      [{^flag, state, prereqs}] -> {state, prereqs}
      [] -> nil
    end
  end

  defp state_on?({:on}), do: true
  defp state_on?(_), do: false

  defp eval({:on}, _flag, _user), do: true
  defp eval({:off}, _flag, _user), do: false
  defp eval({:percentage, pct}, flag, user), do: :erlang.phash2({flag, user}, 100) < pct

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

  def handle_call({:set_state, flag, new_state}, _from, %{table: table} = state) do
    # TODO
  end

  defp existing_prereqs(table, flag) do
    case :ets.lookup(table, flag) do
      [{^flag, _s, ps}] -> ps
      [] -> []
    end
  end

  defp existing_state(table, flag) do
    case :ets.lookup(table, flag) do
      [{^flag, s, _ps}] -> s
      [] -> {:off}
    end
  end

  # Would adding edges flag -> prereqs create a cycle? True if any prereq can
  # already reach `flag` through the existing prerequisite graph.
  defp reaches?(table, from, target, visited) do
    cond do
      from == target ->
        true

      MapSet.member?(visited, from) ->
        false

      true ->
        visited = MapSet.put(visited, from)

        Enum.any?(existing_prereqs(table, from), fn n ->
          reaches?(table, n, target, visited)
        end)
    end
  end
end
```

Give me only the complete implementation of `handle_call` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
