# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DBCleaner do
  @moduledoc """
  Ensures database isolation between integration tests by cleaning up state
  between test runs.

  ## Strategies

  ### `:transaction`
  Wraps each test in a database transaction that is rolled back in `clean/0`.
  Fast and zero-footprint, but requires `async: false` because all test
  interactions must share the single checked-out connection.

  `start/2` calls `repo.begin_transaction/0` on the given repo module.
  `clean/0` calls `repo.rollback/0`.

  ### `:truncation`
  Does no setup work. `clean/0` issues a
  `TRUNCATE <table> RESTART IDENTITY CASCADE` for every table listed in
  `:tables` by calling `repo.query!(repo, sql, [])`.
  Works with any test configuration but is slower due to WAL writes and
  sequence resets.

  ## Usage

      setup do
        {:ok, _} = DBCleaner.start(:transaction, repo: MyApp.Repo)
        # – or –
        {:ok, _} = DBCleaner.start(:truncation, repo: MyApp.Repo, tables: ["users", "posts"])

        on_exit(fn -> DBCleaner.clean() end)
        :ok
      end

  ## State

  All state is stored in the calling process's dictionary under the private key
  `{DBCleaner, :state}`, so no Agent or extra process is required.

  Every `start/2` call discards any previously registered state *before* doing
  any database work, so a failed start can never leave a stale strategy behind.
  """

  @state_key {__MODULE__, :state}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a cleaning strategy for the current test.

  Must be called from the test process (or a `setup` callback) so that the
  state ends up in the correct process dictionary.

  ## Options

    * `:repo`   – (required) the Ecto repo module, e.g. `MyApp.Repo`.
    * `:tables` – list of table-name strings to truncate when using the
                  `:truncation` strategy. Ignored by `:transaction`.

  Returns `{:ok, :transaction | :truncation}` on success, or
  `{:error, reason}` on failure. Any state registered by an earlier `start/2`
  is discarded first, even when this call ultimately fails.
  """
  @spec start(:transaction | :truncation, keyword()) ::
          {:ok, :transaction | :truncation} | {:error, term()}
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    repo = fetch_repo!(opts)

    # Drop any prior registration before touching the database: if
    # begin_transaction/0 raises, no stale strategy may survive this call.
    clear_state()

    try do
      {:ok, _ref} = repo.begin_transaction()
      put_state(%{strategy: :transaction, repo: repo})
      {:ok, :transaction}
    rescue
      e ->
        clear_state()
        {:error, Exception.message(e)}
    end
  end

  def start(:truncation, opts) do
    repo = fetch_repo!(opts)
    tables = Keyword.get(opts, :tables, [])

    clear_state()
    validate_tables!(tables)

    put_state(%{strategy: :truncation, repo: repo, tables: tables})
    {:ok, :truncation}
  end

  def start(unknown, _opts) do
    {:error, "unknown strategy #{inspect(unknown)}. Expected :transaction or :truncation"}
  end

  @doc """
  Cleans up database state based on the strategy passed to `start/2`.

  Call this inside `on_exit/1` so it runs even when a test fails:

      on_exit(fn -> DBCleaner.clean() end)

  ## `:transaction`
  Calls `repo.rollback/0`, discarding every write made during the test.

  ## `:truncation`
  Calls `repo.query!(repo, sql, [])` with a
  `TRUNCATE <table> RESTART IDENTITY CASCADE` statement for every table
  registered in `start/2`.

  Returns `:ok` on success or `{:error, reason}` on failure.
  If `start/2` was never called the function is a safe no-op.
  """
  @spec clean() :: :ok | {:error, term()}
  def clean do
    case get_state() do
      nil -> :ok
      state -> do_clean(state)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers – strategy implementations
  # ---------------------------------------------------------------------------

  defp do_clean(%{strategy: :transaction, repo: repo}) do
    try do
      repo.rollback()
      clear_state()
      :ok
    rescue
      e ->
        clear_state()
        {:error, Exception.message(e)}
    end
  end

  defp do_clean(%{strategy: :truncation, repo: repo, tables: tables}) do
    try do
      Enum.each(tables, fn table ->
        # Table names are validated against a strict allowlist in start/2, so
        # interpolation here is safe — no parameterised query possible for
        # SQL identifiers.
        sql = "TRUNCATE #{table} RESTART IDENTITY CASCADE"
        repo.query!(repo, sql, [])
      end)

      clear_state()
      :ok
    rescue
      e ->
        clear_state()
        {:error, Exception.message(e)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers – validation
  # ---------------------------------------------------------------------------

  # Allows letters, digits, and underscores; must start with a letter or _.
  # Rejects anything that could be used to inject SQL via the table name.
  @valid_identifier ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  defp validate_tables!(tables) when is_list(tables) do
    Enum.each(tables, fn
      table when is_binary(table) ->
        unless Regex.match?(@valid_identifier, table) do
          raise ArgumentError,
                "invalid table name #{inspect(table)}. " <>
                  "Table names must match /[a-zA-Z_][a-zA-Z0-9_]*/"
        end

      other ->
        raise ArgumentError,
              "expected table names to be strings, got: #{inspect(other)}"
    end)
  end

  defp validate_tables!(other) do
    raise ArgumentError, "expected :tables to be a list, got: #{inspect(other)}"
  end

  defp fetch_repo!(opts) do
    case Keyword.fetch(opts, :repo) do
      {:ok, repo} when is_atom(repo) ->
        repo

      {:ok, other} ->
        raise ArgumentError,
              "expected :repo to be an atom (Ecto repo module), got: #{inspect(other)}"

      :error ->
        raise ArgumentError, ":repo is required. Pass repo: MyApp.Repo in opts"
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers – process-dictionary state management
  # ---------------------------------------------------------------------------

  defp put_state(state), do: Process.put(@state_key, state)
  defp get_state, do: Process.get(@state_key)
  defp clear_state, do: Process.delete(@state_key)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DBCleanerTest do
  use ExUnit.Case, async: false

  # --- Fake Repo for deterministic testing ---

  defmodule FakeRepo do
    use Agent

    # Tracks SQL calls made: [{:query, sql} | {:begin} | {:rollback}]
    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)

    # Simulates Ecto.Adapters.SQL.query!/3
    def query!(_repo, sql, _params) do
      Agent.update(__MODULE__, &[{:query, sql} | &1])
      %{rows: [], num_rows: 0}
    end

    # Simulates beginning a transaction
    def begin_transaction do
      Agent.update(__MODULE__, &[{:begin} | &1])
      {:ok, make_ref()}
    end

    # Simulates rolling back
    def rollback do
      Agent.update(__MODULE__, &[{:rollback} | &1])
      :ok
    end
  end

  setup do
    start_supervised!(FakeRepo)
    FakeRepo.reset()
    :ok
  end

  # -------------------------------------------------------
  # :truncation strategy
  # -------------------------------------------------------

  test "truncation: start/2 is a no-op" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    assert FakeRepo.calls() == []
  end

  test "truncation: clean/0 truncates all listed tables" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    DBCleaner.clean()

    calls = FakeRepo.calls()
    assert length(calls) == 2

    sqls = Enum.map(calls, fn {:query, sql} -> sql end)
    assert Enum.any?(sqls, &String.contains?(&1, "users"))
    assert Enum.any?(sqls, &String.contains?(&1, "posts"))
    assert Enum.all?(sqls, &String.contains?(&1, "TRUNCATE"))
  end

  test "truncation: clean/0 includes RESTART IDENTITY CASCADE" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["events"])
    DBCleaner.clean()

    [{:query, sql}] = FakeRepo.calls()
    assert String.contains?(sql, "RESTART IDENTITY")
    assert String.contains?(sql, "CASCADE")
  end

  test "truncation: empty tables list results in no queries" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: [])
    DBCleaner.clean()
    assert FakeRepo.calls() == []
  end

  test "truncation: clean/0 is safe to call without a prior start (no crash)" do
    # Should either be a no-op or raise a clear error, but must not crash the test process
    DBCleaner.clean()
  rescue
    _ -> :ok
  end

  # -------------------------------------------------------
  # :transaction strategy
  # -------------------------------------------------------

  test "transaction: start/2 begins a transaction" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    assert {:begin} in FakeRepo.calls()
  end

  test "transaction: clean/0 rolls back the transaction" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    FakeRepo.reset()

    DBCleaner.clean()

    assert {:rollback} in FakeRepo.calls()
  end

  test "transaction: no truncation queries are issued on clean/0" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: ["users"])
    FakeRepo.reset()

    DBCleaner.clean()

    refute Enum.any?(FakeRepo.calls(), fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end

  # -------------------------------------------------------
  # State isolation between strategies
  # -------------------------------------------------------

  test "switching strategy between tests does not bleed state" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["orders"])
    DBCleaner.clean()
    truncation_calls = FakeRepo.calls()

    FakeRepo.reset()

    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    DBCleaner.clean()
    transaction_calls = FakeRepo.calls()

    # Truncation run produced TRUNCATE queries, transaction run did not
    assert Enum.any?(truncation_calls, fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)

    refute Enum.any?(transaction_calls, fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end

  # -------------------------------------------------------
  # Isolation guarantee (behavioral)
  # -------------------------------------------------------

  test "truncation: records inserted between start and clean are gone after clean" do
    # Simulate an in-memory 'table' to stand in for a real DB
    {:ok, table} = Agent.start_link(fn -> [] end)

    insert = fn row -> Agent.update(table, &[row | &1]) end
    all = fn -> Agent.get(table, & &1) end
    truncate = fn -> Agent.update(table, fn _ -> [] end) end

    # Override clean behaviour inline for this test
    insert.(%{id: 1, name: "Alice"})
    assert length(all.()) == 1

    truncate.()
    assert all.() == []

    # Second test run: table is clean at the start
    insert.(%{id: 2, name: "Bob"})
    assert length(all.()) == 1
  end

  test "transaction: rollback leaves the table unchanged" do
    {:ok, table} = Agent.start_link(fn -> ["existing"] end)

    snapshot = Agent.get(table, & &1)

    # 'Begin' captures snapshot, inserts happen, rollback restores
    Agent.update(table, &["new_record" | &1])
    assert length(Agent.get(table, & &1)) == 2

    # Rollback = restore snapshot
    Agent.update(table, fn _ -> snapshot end)
    assert Agent.get(table, & &1) == ["existing"]
  end

  # -------------------------------------------------------
  # Return values pinned by the prompt
  # -------------------------------------------------------

  test "clean/0 without a prior start/2 returns :ok" do
    assert DBCleaner.clean() == :ok
  end

  # -------------------------------------------------------
  # Return shapes of start/2 and clean/0 pinned by the prompt
  # -------------------------------------------------------

  defmodule BeginRaisesRepo do
    def begin_transaction do
      raise RuntimeError, "begin_transaction exploded"
    end
  end

  defmodule CleanRaisesRepo do
    def begin_transaction, do: {:ok, make_ref()}

    def rollback do
      raise RuntimeError, "rollback exploded"
    end

    def query!(_repo, _sql, _params) do
      raise RuntimeError, "query! exploded"
    end
  end

  test "transaction: start/2 returns {:ok, :transaction} on success" do
    assert DBCleaner.start(:transaction, repo: FakeRepo) == {:ok, :transaction}
  end

  test "truncation: start/2 returns {:ok, :truncation} on success" do
    assert DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"]) == {:ok, :truncation}
  end

  test "start/2 with an unknown strategy returns {:error, message} with a String message" do
    assert {:error, message} = DBCleaner.start(:bogus, repo: FakeRepo)
    assert is_binary(message)
  end

  test "transaction: a raise from begin_transaction/0 is rescued into {:error, message}" do
    assert {:error, message} = DBCleaner.start(:transaction, repo: BeginRaisesRepo)
    assert is_binary(message)
  end

  test "transaction: clean/0 returns :ok on success" do
    # TODO
  end

  test "truncation: clean/0 returns :ok on success" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok
  end

  test "transaction: a raise from rollback/0 makes clean/0 return {:error, message}" do
    DBCleaner.start(:transaction, repo: CleanRaisesRepo)
    assert {:error, message} = DBCleaner.clean()
    assert is_binary(message)
  end

  test "truncation: a raise from query!/3 makes clean/0 return {:error, message}" do
    DBCleaner.start(:truncation, repo: CleanRaisesRepo, tables: ["users"])
    assert {:error, message} = DBCleaner.clean()
    assert is_binary(message)
  end

  test "a failed transaction start/2 still replaces prior truncation state (no TRUNCATE on clean)" do
    assert {:ok, :truncation} =
             DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])

    assert {:error, message} = DBCleaner.start(:transaction, repo: BeginRaisesRepo)
    assert is_binary(message)

    FakeRepo.reset()
    DBCleaner.clean()

    refute Enum.any?(FakeRepo.calls(), fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end

  test "truncation: clean/0 emits the exact bare-identifier TRUNCATE statement per table" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    DBCleaner.clean()

    assert FakeRepo.calls() == [
             {:query, "TRUNCATE users RESTART IDENTITY CASCADE"},
             {:query, "TRUNCATE posts RESTART IDENTITY CASCADE"}
           ]
  end

  test "start/2 replaces an uncleaned truncation registration with a transaction one" do
    assert {:ok, :truncation} =
             DBCleaner.start(:truncation, repo: FakeRepo, tables: ["orders"])

    assert {:ok, :transaction} = DBCleaner.start(:transaction, repo: FakeRepo)

    FakeRepo.reset()
    assert DBCleaner.clean() == :ok

    calls = FakeRepo.calls()
    assert {:rollback} in calls

    refute Enum.any?(calls, fn
             {:query, _sql} -> true
             _ -> false
           end)
  end

  test "transaction: clean/0 issues no query!/3 call at all even when tables were given" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: ["users", "posts"])
    FakeRepo.reset()

    assert DBCleaner.clean() == :ok

    assert FakeRepo.calls() == [{:rollback}]
  end

  test "truncation: a second clean/0 after cleanup issues no further TRUNCATE statements" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok
    FakeRepo.reset()

    assert DBCleaner.clean() == :ok
    assert FakeRepo.calls() == []
  end

  test "truncation: query!/3 receives the repo module itself and empty params" do
    defmodule EchoRepo do
      def query!(repo, sql, params) do
        send(self(), {:echo_query, repo, sql, params})
        %{rows: [], num_rows: 0}
      end
    end

    DBCleaner.start(:truncation, repo: EchoRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok

    assert_receive {:echo_query, EchoRepo, "TRUNCATE users RESTART IDENTITY CASCADE", []}, 100
    refute_receive {:echo_query, _, _, _}, 50
  end

  # -------------------------------------------------------
  # Isolation guarantee driven through the DBCleaner API
  # -------------------------------------------------------

  # A stand-in repo holding rows for several tables. It applies the documented
  # effects of the calls DBCleaner is specified to make: a
  # `TRUNCATE <table> RESTART IDENTITY CASCADE` statement received through
  # query!/3 empties that one table, begin_transaction/0 snapshots the rows and
  # rollback/0 restores the snapshot.
  defmodule TableRepo do
    use Agent

    @truncate ~r/\ATRUNCATE ([a-zA-Z_][a-zA-Z0-9_]*) RESTART IDENTITY CASCADE\z/

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> %{rows: [], snapshot: nil} end, name: __MODULE__)
    end

    def insert(table, row) do
      Agent.update(__MODULE__, fn state ->
        %{state | rows: state.rows ++ [{table, row}]}
      end)
    end

    def rows(table) do
      Agent.get(__MODULE__, fn state ->
        for {name, row} <- state.rows, name == table, do: row
      end)
    end

    def begin_transaction do
      Agent.update(__MODULE__, fn state -> %{state | snapshot: state.rows} end)
      {:ok, make_ref()}
    end

    def rollback do
      Agent.update(__MODULE__, fn state ->
        %{state | rows: state.snapshot || [], snapshot: nil}
      end)

      :ok
    end

    def query!(_repo, sql, _params) do
      case Regex.run(@truncate, sql) do
        [_, table] ->
          Agent.update(__MODULE__, fn state ->
            %{state | rows: Enum.reject(state.rows, fn {name, _row} -> name == table end)}
          end)

        nil ->
          :ok
      end

      %{rows: [], num_rows: 0}
    end
  end

  test "truncation: rows written between start/2 and clean/0 are gone from the listed tables" do
    start_supervised!(TableRepo)

    assert {:ok, :truncation} =
             DBCleaner.start(:truncation, repo: TableRepo, tables: ["users", "posts"])

    TableRepo.insert("users", %{id: 1, name: "Alice"})
    TableRepo.insert("posts", %{id: 1, title: "Hello"})
    TableRepo.insert("audits", %{id: 1, event: "login"})

    assert DBCleaner.clean() == :ok

    assert TableRepo.rows("users") == []
    assert TableRepo.rows("posts") == []
    # Unlisted tables receive no statement, so their rows survive cleanup.
    assert TableRepo.rows("audits") == [%{id: 1, event: "login"}]
  end

  test "transaction: rows written between start/2 and clean/0 do not survive the rollback" do
    start_supervised!(TableRepo)

    TableRepo.insert("users", %{id: 1, name: "Existing"})

    assert {:ok, :transaction} =
             DBCleaner.start(:transaction, repo: TableRepo, tables: ["users"])

    TableRepo.insert("users", %{id: 2, name: "Bob"})
    assert length(TableRepo.rows("users")) == 2

    assert DBCleaner.clean() == :ok

    # The rollback undoes the test's write; rows present before start/2 remain,
    # since this strategy issues no TRUNCATE for the listed table.
    assert TableRepo.rows("users") == [%{id: 1, name: "Existing"}]
  end
end
```
