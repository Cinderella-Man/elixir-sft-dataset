# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @impl true
  def init(%{table_name: table_name}) do
    table =
      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])

    :persistent_term.put(@pt_server, self())
    :persistent_term.put(@pt_table, table)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:set, flag_name, value}, _from, %{table: table} = state) do
    :ets.insert(table, {flag_name, value})
    {:reply, :ok, state}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule FeatureFlagsTest do
  use ExUnit.Case, async: false

  setup do
    # Start with default options; every assertion below observes the store
    # purely through its documented public API.
    pid = start_supervised!(FeatureFlags)
    %{pid: pid}
  end

  test "unknown flag has :off variant and is not enabled" do
    assert FeatureFlags.variant_for(:nope, "u1") == :off
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u1")
  end

  test "enable makes flag :on for everyone" do
    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled?(:feat)
    assert FeatureFlags.variant_for(:feat, "u1") == :on
    assert FeatureFlags.enabled_for?(:feat, "u1")
  end

  test "disable sets :off" do
    FeatureFlags.enable(:feat)
    FeatureFlags.disable(:feat)
    assert FeatureFlags.variant_for(:feat, "u1") == :off
    refute FeatureFlags.enabled_for?(:feat, "u1")
  end

  test "variant flags are not globally enabled?" do
    # TODO
  end

  test "assignment is deterministic across calls" do
    FeatureFlags.set_variants(:exp, [{:a, 34}, {:b, 33}, {:c, 33}])
    first = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    second = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    assert first == second
  end

  test "assignment matches the cumulative-bucket formula" do
    variants = [{:a, 50}, {:b, 30}, {:c, 20}]
    FeatureFlags.set_variants(:exp, variants)

    for i <- 1..300 do
      user = "user:#{i}"
      bucket = :erlang.phash2({:exp, user}, 100)

      expected =
        cond do
          bucket < 50 -> :a
          bucket < 80 -> :b
          true -> :c
        end

      assert FeatureFlags.variant_for(:exp, user) == expected
    end
  end

  test "distribution roughly matches weights" do
    FeatureFlags.set_variants(:exp, [{:a, 70}, {:b, 30}])
    assignments = for i <- 1..2000, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    a = Enum.count(assignments, &(&1 == :a))
    b = Enum.count(assignments, &(&1 == :b))

    assert a + b == 2000
    assert a >= 1300 and a <= 1500
    assert b >= 500 and b <= 700
  end

  test "zero-weight variant receives no users" do
    FeatureFlags.set_variants(:exp, [{:a, 100}, {:z, 0}])
    assignments = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    assert Enum.all?(assignments, &(&1 == :a))
    refute Enum.any?(assignments, &(&1 == :z))
  end

  test "set_variants rejects weights that do not sum to 100" do
    assert_raise ArgumentError, fn ->
      FeatureFlags.set_variants(:bad, [{:a, 50}, {:b, 40}])
    end
  end

  test "updating variants takes effect immediately" do
    FeatureFlags.set_variants(:exp, [{:a, 100}, {:b, 0}])
    assert FeatureFlags.variant_for(:exp, "u1") == :a
    FeatureFlags.set_variants(:exp, [{:a, 0}, {:b, 100}])
    assert FeatureFlags.variant_for(:exp, "u1") == :b
  end

  test "flags are independent" do
    FeatureFlags.enable(:x)
    FeatureFlags.set_variants(:y, [{:a, 100}])
    assert FeatureFlags.variant_for(:x, "u") == :on
    assert FeatureFlags.variant_for(:y, "u") == :a
  end

  test "concurrent reads are consistent" do
    FeatureFlags.set_variants(:exp, [{:a, 100}])
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.variant_for(:exp, "u1") end)
    assert Enum.all?(Task.await_many(tasks), &(&1 == :a))
  end

  test "default options create the named :feature_flags set table owned by the server",
       %{pid: pid} do
    assert :ets.info(:feature_flags, :owner) == pid
    assert :ets.info(:feature_flags, :type) == :set
    assert :ets.info(:feature_flags, :named_table) == true
    assert :ets.info(:feature_flags, :read_concurrency) == true
  end

  test "table_name option creates that table and flag reads resolve against it" do
    table = unique_name("ff_table")
    assert :ets.info(table) == :undefined

    pid =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: unique_name("ff_srv")]},
        id: :custom_table_server
      )

    assert :ets.info(table, :owner) == pid
    assert :ets.info(table, :type) == :set
    assert :ets.info(table, :named_table) == true
    assert :ets.info(table, :read_concurrency) == true

    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled?(:feat)

    FeatureFlags.set_variants(:exp, [{:a, 100}])
    assert FeatureFlags.variant_for(:exp, "u1") == :a
  end

  test "name option registers the server process under that name" do
    name = unique_name("ff_named")
    table = unique_name("ff_table")

    pid =
      start_supervised!({FeatureFlags, [table_name: table, name: name]}, id: :named_server)

    assert Process.whereis(name) == pid
  end

  test "name nil starts the server without registering it" do
    table = unique_name("ff_table")

    pid =
      start_supervised!({FeatureFlags, [table_name: table, name: nil]}, id: :anonymous_server)

    assert Process.info(pid, :registered_name) == {:registered_name, []}
    assert :ets.info(table, :owner) == pid
  end

  defp unique_name(prefix) do
    String.to_atom("#{prefix}_#{System.pid()}_#{System.unique_integer([:positive])}")
  end
end
```
