# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

  @impl true
  def handle_call({:set_state, flag, new_state}, _from, %{table: table} = state) do
    prereqs = existing_prereqs(table, flag)
    :ets.insert(table, {flag, new_state, prereqs})
    {:reply, :ok, state}
  end

  def handle_call({:set_prereqs, flag, prereqs}, _from, %{table: table} = state) do
    reply =
      if Enum.any?(prereqs, fn p -> reaches?(table, p, flag, MapSet.new()) end) do
        {:error, :cycle}
      else
        cur_state = existing_state(table, flag)
        :ets.insert(table, {flag, cur_state, prereqs})
        :ok
      end

    {:reply, reply, state}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule FeatureFlagsTest do
  use ExUnit.Case, async: false

  setup do
    table = :feature_flags_test
    {:ok, pid} = FeatureFlags.start_link(table_name: table, name: nil)
    %{pid: pid, table: table}
  end

  test "unknown flag defaults to false" do
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u")
    assert FeatureFlags.prerequisites(:nope) == []
  end

  test "enable / disable without prerequisites" do
    FeatureFlags.enable(:f)
    assert FeatureFlags.enabled?(:f)
    FeatureFlags.disable(:f)
    refute FeatureFlags.enabled?(:f)
  end

  test "percentage evaluation is deterministic and gated by phash2" do
    FeatureFlags.enable_for_percentage(:beta, 40)
    refute FeatureFlags.enabled?(:beta)

    for i <- 1..200 do
      user = "u#{i}"
      expected = :erlang.phash2({:beta, user}, 100) < 40
      assert FeatureFlags.enabled_for?(:beta, user) == expected
    end
  end

  test "dependent flag is disabled until its prerequisite is enabled" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:parent])
    refute FeatureFlags.enabled?(:child)
    FeatureFlags.enable(:parent)
    assert FeatureFlags.enabled?(:child)
    FeatureFlags.disable(:parent)
    refute FeatureFlags.enabled?(:child)
  end

  test "enabled_for? requires prerequisites for the same user" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:gate])
    FeatureFlags.enable_for_percentage(:gate, 50)

    for i <- 1..300 do
      user = "u#{i}"
      gate_open = :erlang.phash2({:gate, user}, 100) < 50
      assert FeatureFlags.enabled_for?(:child, user) == gate_open
    end
  end

  test "prerequisites are transitive" do
    FeatureFlags.enable(:a)
    FeatureFlags.enable(:b)
    FeatureFlags.enable(:c)
    FeatureFlags.set_prerequisites(:b, [:a])
    FeatureFlags.set_prerequisites(:c, [:b])
    assert FeatureFlags.enabled?(:c)
    FeatureFlags.disable(:a)
    refute FeatureFlags.enabled?(:c)
  end

  test "cycles are rejected and leave the graph unchanged" do
    # TODO
  end

  test "self-dependency is rejected" do
    assert {:error, :cycle} = FeatureFlags.set_prerequisites(:x, [:x])
  end

  test "setting state preserves prerequisites and vice versa" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:parent])
    assert FeatureFlags.prerequisites(:child) == [:parent]

    FeatureFlags.disable(:child)
    assert FeatureFlags.prerequisites(:child) == [:parent]

    FeatureFlags.set_prerequisites(:child, [:parent, :other])
    FeatureFlags.enable(:parent)
    FeatureFlags.enable(:other)
    refute FeatureFlags.enabled?(:child)

    FeatureFlags.enable(:child)
    assert FeatureFlags.enabled?(:child)
  end

  test "concurrent reads are consistent" do
    FeatureFlags.enable(:p)
    FeatureFlags.enable(:c)
    FeatureFlags.set_prerequisites(:c, [:p])
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.enabled?(:c) end)
    assert Enum.all?(Task.await_many(tasks), & &1)
  end

  test "an explicit :name registers the process and writes still reach it" do
    table = unique_atom("ff_named_table")
    name = unique_atom("ff_named_server")
    {:ok, pid} = FeatureFlags.start_link(table_name: table, name: name)

    assert Process.whereis(name) == pid

    FeatureFlags.enable(:registered_flag)
    assert FeatureFlags.enabled?(:registered_flag)

    :ok = GenServer.stop(pid)
  end

  test "omitting :name registers the process under the module name" do
    table = unique_atom("ff_default_name_table")
    {:ok, pid} = FeatureFlags.start_link(table_name: table)

    assert Process.whereis(FeatureFlags) == pid

    :ok = GenServer.stop(pid)
  end

  test "percentage 0 excludes every user and percentage 100 includes every user" do
    FeatureFlags.enable_for_percentage(:pct_zero, 0)
    FeatureFlags.enable_for_percentage(:pct_full, 100)

    for i <- 1..150 do
      user = "pct_user#{i}"
      refute FeatureFlags.enabled_for?(:pct_zero, user)
      assert FeatureFlags.enabled_for?(:pct_full, user)
    end
  end

  test "a percentage outside 0..100 is not accepted" do
    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:pct_over, 101)
    end

    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:pct_under, -1)
    end
  end

  test "an :off flag is disabled for every user, not just under enabled?/1" do
    FeatureFlags.enable(:switch)
    assert FeatureFlags.enabled_for?(:switch, "user-a")

    FeatureFlags.disable(:switch)
    refute FeatureFlags.enabled_for?(:switch, "user-a")
    refute FeatureFlags.enabled_for?(:switch, "user-b")
  end

  test "set_prerequisites returns :ok when the edges introduce no cycle" do
    assert FeatureFlags.set_prerequisites(:sp_mid, [:sp_root]) == :ok
    assert FeatureFlags.set_prerequisites(:sp_leaf, [:sp_mid]) == :ok
    assert FeatureFlags.set_prerequisites(:sp_leaf, [:sp_mid, :sp_root]) == :ok
    assert FeatureFlags.prerequisites(:sp_leaf) == [:sp_mid, :sp_root]
  end

  test "the ETS table exists once start_link returns, as a set owned by the server" do
    table = unique_atom("ff_table_shape")
    {:ok, pid} = FeatureFlags.start_link(table_name: table, name: nil)

    assert :ets.info(table, :type) == :set
    assert :ets.info(table, :named_table) == true
    assert :ets.info(table, :read_concurrency) == true
    assert :ets.info(table, :owner) == pid

    :ok = GenServer.stop(pid)
  end

  # Distinct atom per test run so concurrently living servers and ETS tables
  # from other runs of this file never collide.
  defp unique_atom(prefix) do
    :"#{prefix}_#{System.pid()}_#{System.unique_integer([:positive])}"
  end
end
```
