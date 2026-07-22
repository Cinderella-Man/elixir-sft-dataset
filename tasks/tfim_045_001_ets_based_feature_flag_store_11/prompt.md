# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  # -------------------------------------------------------
  # Basic enable / disable
  # -------------------------------------------------------

  test "unknown flag defaults to false" do
    refute FeatureFlags.enabled?(:nonexistent)
    refute FeatureFlags.enabled_for?(:nonexistent, "user:1")
  end

  test "enable sets the flag on for everyone" do
    FeatureFlags.enable(:my_feature)
    assert FeatureFlags.enabled?(:my_feature)
  end

  test "disable sets the flag off for everyone" do
    FeatureFlags.enable(:my_feature)
    FeatureFlags.disable(:my_feature)
    refute FeatureFlags.enabled?(:my_feature)
  end

  test "enabled_for? returns true when flag is :on" do
    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled_for?(:feat, "user:1")
    assert FeatureFlags.enabled_for?(:feat, "user:2")
  end

  test "enabled_for? returns false when flag is :off" do
    FeatureFlags.enable(:feat)
    FeatureFlags.disable(:feat)
    refute FeatureFlags.enabled_for?(:feat, "user:99")
  end

  # -------------------------------------------------------
  # Percentage rollout
  # -------------------------------------------------------

  test "enabled? returns false for percentage flags" do
    FeatureFlags.enable_for_percentage(:beta, 50)
    refute FeatureFlags.enabled?(:beta)
  end

  test "0% lets nobody through" do
    FeatureFlags.enable_for_percentage(:feat, 0)

    results =
      for i <- 1..200 do
        FeatureFlags.enabled_for?(:feat, "user:#{i}")
      end

    assert Enum.all?(results, &(&1 == false))
  end

  test "100% lets everyone through" do
    FeatureFlags.enable_for_percentage(:feat, 100)

    results =
      for i <- 1..200 do
        FeatureFlags.enabled_for?(:feat, "user:#{i}")
      end

    assert Enum.all?(results, &(&1 == true))
  end

  test "50% rollout enables roughly half of users" do
    FeatureFlags.enable_for_percentage(:rollout, 50)

    enabled_count =
      for i <- 1..1_000 do
        FeatureFlags.enabled_for?(:rollout, "user:#{i}")
      end
      |> Enum.count(& &1)

    # Deterministic hash — we just verify it's in a sensible range
    assert enabled_count >= 400
    assert enabled_count <= 600
  end

  test "percentage rollout is deterministic — same user always gets same result" do
    # TODO
  end

  test "phash2 bucketing is consistent with expected formula" do
    FeatureFlags.enable_for_percentage(:p, 10)

    for i <- 1..200 do
      result = FeatureFlags.enabled_for?(:p, "user:#{i}")
      expected = :erlang.phash2({:p, "user:#{i}"}, 100) < 10

      assert result == expected,
             "user:#{i} — got #{result}, expected #{expected}"
    end
  end

  # -------------------------------------------------------
  # Flag state transitions
  # -------------------------------------------------------

  test "flag transitions from :on → :percentage → :off correctly" do
    FeatureFlags.enable(:flag)
    assert FeatureFlags.enabled?(:flag)

    FeatureFlags.enable_for_percentage(:flag, 50)
    refute FeatureFlags.enabled?(:flag)

    FeatureFlags.disable(:flag)
    refute FeatureFlags.enabled_for?(:flag, "any_user")
  end

  test "updating percentage takes effect immediately" do
    FeatureFlags.enable_for_percentage(:staged, 0)
    refute FeatureFlags.enabled_for?(:staged, "user:1")

    FeatureFlags.enable_for_percentage(:staged, 100)
    assert FeatureFlags.enabled_for?(:staged, "user:1")
  end

  # -------------------------------------------------------
  # Multiple flags are independent
  # -------------------------------------------------------

  test "flags are independent of each other" do
    FeatureFlags.enable(:flag_a)
    FeatureFlags.disable(:flag_b)

    assert FeatureFlags.enabled?(:flag_a)
    refute FeatureFlags.enabled?(:flag_b)
  end

  # -------------------------------------------------------
  # Concurrent reads
  # -------------------------------------------------------

  test "concurrent reads return consistent results" do
    FeatureFlags.enable(:concurrent_flag)

    tasks =
      for _ <- 1..50 do
        Task.async(fn -> FeatureFlags.enabled?(:concurrent_flag) end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, & &1)
  end

  # -------------------------------------------------------
  # Table shape and start_link options
  # -------------------------------------------------------

  test "default table is a named :set called :feature_flags owned by the server", %{pid: pid} do
    assert :ets.info(:feature_flags, :name) == :feature_flags
    assert :ets.info(:feature_flags, :named_table) == true
    assert :ets.info(:feature_flags, :type) == :set
    assert :ets.info(:feature_flags, :owner) == pid
  end

  test "start_link honours :table_name and :name options" do
    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("flags_table_#{suffix}")
    server = String.to_atom("flags_server_#{suffix}")

    pid =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: server]},
        id: :custom_feature_flags
      )

    # The process is registered under the requested name...
    assert Process.whereis(server) == pid

    # ...and the ETS table carries the requested name, not the default.
    assert :ets.info(table, :name) == table
    assert :ets.info(table, :named_table) == true
    assert :ets.info(table, :type) == :set
    assert :ets.info(table, :owner) == pid
  end

  test ":table_name backs the new server with its own store, not the default table",
       %{pid: default_pid} do
    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("opts_table_#{suffix}")
    server = String.to_atom("opts_server_#{suffix}")

    # Seed a flag through the default server, then bring up a second server
    # configured with its own table and registration name.
    FeatureFlags.enable(:seeded_in_default)
    assert :ets.lookup(:feature_flags, :seeded_in_default) != []

    pid =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: server]},
        id: :opts_feature_flags
      )

    # A distinct process owns a distinct table: the configured table is empty
    # of the default table's flags rather than an alias for it.
    assert pid != default_pid
    assert Process.whereis(server) == pid
    assert :ets.info(table, :owner) == pid
    assert :ets.lookup(table, :seeded_in_default) == []
  end

  # -------------------------------------------------------
  # Reads bypass the GenServer process
  # -------------------------------------------------------

  test "enabled? and enabled_for? read from ETS while the server is unavailable", %{pid: pid} do
    FeatureFlags.enable(:direct_read)
    FeatureFlags.enable_for_percentage(:direct_pct, 100)

    # With the owning process suspended it cannot serve any call; reads must
    # still answer because they go straight to the named ETS table.
    :sys.suspend(pid)

    reader =
      Task.async(fn ->
        {FeatureFlags.enabled?(:direct_read), FeatureFlags.enabled_for?(:direct_pct, "user:1")}
      end)

    outcome = Task.yield(reader, 1_000) || Task.shutdown(reader, :brutal_kill)

    :sys.resume(pid)

    assert outcome == {:ok, {true, true}}
  end

  test "reads deliver no message to the server while writes do", %{pid: pid} do
    FeatureFlags.enable(:traced_on)
    FeatureFlags.enable_for_percentage(:traced_pct, 100)

    :erlang.trace(pid, true, [:receive])

    try do
      # Every read answers correctly from the named table...
      assert FeatureFlags.enabled?(:traced_on)
      assert FeatureFlags.enabled_for?(:traced_pct, "user:1")
      refute FeatureFlags.enabled?(:traced_pct)
      refute FeatureFlags.enabled_for?(:traced_unknown, "user:1")

      # ...without the server process receiving anything at all.
      refute_receive {:trace, ^pid, :receive, _}, 200

      # A write, by contrast, is serialised through the server, which proves
      # the observation above was not silently blind.
      FeatureFlags.enable(:traced_write)
      assert_receive {:trace, ^pid, :receive, _}, 1_000
    after
      :erlang.trace(pid, false, [:receive])
    end
  end

  test "writes stall while the owning server is suspended and land once it resumes", %{pid: pid} do
    # A suspended GenServer cannot serve calls. If the writes really go through
    # the server, none of them can take effect until it is resumed again.
    :sys.suspend(pid)

    writers = [
      Task.async(fn -> FeatureFlags.enable(:write_path_on) end),
      Task.async(fn -> FeatureFlags.disable(:write_path_off) end),
      Task.async(fn -> FeatureFlags.enable_for_percentage(:write_path_pct, 100) end)
    ]

    assert Enum.all?(writers, fn task -> Task.yield(task, 200) == nil end)
    refute FeatureFlags.enabled?(:write_path_on)
    refute FeatureFlags.enabled_for?(:write_path_pct, "user:1")

    :sys.resume(pid)

    assert Enum.map(writers, &Task.await(&1, 1_000)) == [:ok, :ok, :ok]
    assert FeatureFlags.enabled?(:write_path_on)
    assert FeatureFlags.enabled_for?(:write_path_pct, "user:1")
  end

  test "ETS tables are created with read_concurrency enabled, default and custom" do
    assert :ets.info(:feature_flags, :read_concurrency) == true

    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("rc_table_#{suffix}")
    server = String.to_atom("rc_server_#{suffix}")

    start_supervised!(
      {FeatureFlags, [table_name: table, name: server]},
      id: :read_concurrency_feature_flags
    )

    assert :ets.info(table, :read_concurrency) == true
  end

  test "enable_for_percentage refuses non-integer or out-of-range percentages" do
    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:guarded, 101)
    end

    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:guarded, -1)
    end

    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:guarded, 50.0)
    end

    # No rejected call may leave a flag behind.
    refute FeatureFlags.enabled?(:guarded)
    refute FeatureFlags.enabled_for?(:guarded, "user:1")
  end

  test "user hashing exactly to the threshold is excluded until the threshold grows" do
    target = 25

    user_id =
      Enum.find_value(1..50_000, fn i ->
        candidate = "user:#{i}"
        if :erlang.phash2({:edge, candidate}, 100) == target, do: candidate
      end)

    assert user_id, "expected some user hashing to exactly #{target} for flag :edge"

    FeatureFlags.enable_for_percentage(:edge, target)
    refute FeatureFlags.enabled_for?(:edge, user_id)

    FeatureFlags.enable_for_percentage(:edge, target + 1)
    assert FeatureFlags.enabled_for?(:edge, user_id)
  end

  test "the most recently started instance serves the module-level API", %{pid: default_pid} do
    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("routed_table_#{suffix}")
    server = String.to_atom("routed_server_#{suffix}")

    second =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: server]},
        id: :routed_flags
      )

    # Writes route to the LAST-started instance: the flag lands in ITS
    # table (presence only — the stored value shape is the module's own
    # business), owned by the second server...
    assert :ok = FeatureFlags.enable(:routed_flag)
    assert [{:routed_flag, _}] = :ets.lookup(table, :routed_flag)
    assert :ets.info(table, :owner) == second

    # ...module-level reads serve it through the published table...
    assert FeatureFlags.enabled?(:routed_flag)

    # ...and the default instance's table never saw the write.
    assert :ets.lookup(:feature_flags, :routed_flag) == []
    assert :ets.info(:feature_flags, :owner) == default_pid
  end
end
```
