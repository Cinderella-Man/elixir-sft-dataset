# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    FeatureFlags.enable_for_percentage(:stable, 40)

    first_pass =
      for i <- 1..500, do: FeatureFlags.enabled_for?(:stable, "user:#{i}")

    second_pass =
      for i <- 1..500, do: FeatureFlags.enabled_for?(:stable, "user:#{i}")

    assert first_pass == second_pass
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
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
