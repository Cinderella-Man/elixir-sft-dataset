# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
  defp hist_table, do: :persistent_term.get(@pt_hist)

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

## Test harness — implement the `# TODO` test

```elixir
defmodule FeatureFlagsTest do
  use ExUnit.Case, async: false

  setup do
    table = :feature_flags_test
    {:ok, pid} = FeatureFlags.start_link(table_name: table, name: nil)
    %{pid: pid, table: table}
  end

  test "unknown flag defaults" do
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u")
    assert FeatureFlags.version(:nope) == 0
    assert FeatureFlags.history(:nope) == []
  end

  test "enable then read at version 1" do
    FeatureFlags.enable(:f)
    assert FeatureFlags.enabled?(:f)
    assert FeatureFlags.version(:f) == 1
  end

  test "each write bumps the version" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    FeatureFlags.enable_for_percentage(:f, 25)
    assert FeatureFlags.version(:f) == 3
  end

  test "history records every state in ascending version order" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    FeatureFlags.enable_for_percentage(:f, 25)

    assert FeatureFlags.history(:f) == [
             {1, {:on}},
             {2, {:off}},
             {3, {:percentage, 25}}
           ]
  end

  test "percentage flag is not globally enabled but deterministic per user" do
    FeatureFlags.enable_for_percentage(:beta, 40)
    refute FeatureFlags.enabled?(:beta)

    for i <- 1..200 do
      user = "u#{i}"
      expected = :erlang.phash2({:beta, user}, 100) < 40
      assert FeatureFlags.enabled_for?(:beta, user) == expected
    end
  end

  test "rollback reverts to the previous state as a new version" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    assert :ok = FeatureFlags.rollback(:f)
    assert FeatureFlags.enabled?(:f)
    assert FeatureFlags.version(:f) == 3

    assert FeatureFlags.history(:f) == [
             {1, {:on}},
             {2, {:off}},
             {3, {:on}}
           ]
  end

  test "rollback chains correctly through multiple versions" do
    FeatureFlags.enable_for_percentage(:f, 10)
    FeatureFlags.enable_for_percentage(:f, 50)
    FeatureFlags.rollback(:f)
    assert FeatureFlags.version(:f) == 3
    refute FeatureFlags.enabled_for?(:f, "u") == FeatureFlags.enabled_for?(:f, "u") == false and false
    # the current state should equal version 1's {:percentage, 10}
    assert List.last(FeatureFlags.history(:f)) == {3, {:percentage, 10}}
  end

  test "rollback fails when there is no previous version" do
    # TODO
  end

  test "rollback fails for unknown flag" do
    assert {:error, :unknown_flag} = FeatureFlags.rollback(:ghost)
  end

  test "flags maintain independent histories" do
    FeatureFlags.enable(:a)
    FeatureFlags.disable(:b)
    FeatureFlags.disable(:a)
    assert FeatureFlags.version(:a) == 2
    assert FeatureFlags.version(:b) == 1
    assert FeatureFlags.history(:b) == [{1, {:off}}]
  end

  test "concurrent reads are consistent" do
    FeatureFlags.enable(:c)
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.enabled?(:c) end)
    assert Enum.all?(Task.await_many(tasks), & &1)
  end
end
```
