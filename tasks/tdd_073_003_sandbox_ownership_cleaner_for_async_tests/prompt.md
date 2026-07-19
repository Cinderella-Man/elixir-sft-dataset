# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule DBCleanerTest do
  use ExUnit.Case, async: false

  defmodule FakeRepo do
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)

    def checkout do
      ref = make_ref()
      Agent.update(__MODULE__, &[{:checkout, ref} | &1])
      ref
    end

    def checkin(ref) do
      Agent.update(__MODULE__, &[{:checkin, ref} | &1])
      :ok
    end
  end

  setup do
    start_supervised!(FakeRepo)
    FakeRepo.reset()
    start_supervised!(%{id: :dbc_registry, start: {DBCleaner, :ensure_registry, []}})
    :ok
  end

  test "start/2 checks out a connection and registers the owner" do
    assert {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
    assert Enum.any?(FakeRepo.calls(), &match?({:checkout, _}, &1))
    assert {:ok, ^conn} = DBCleaner.lookup()
  end

  test "a non-owner, non-allowed process cannot resolve a connection" do
    DBCleaner.start(:sandbox, repo: FakeRepo)
    parent = self()
    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, :error}, 1000
  end

  test "allow/2 grants a second process access to the owner's connection" do
    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    parent = self()

    child =
      spawn(fn ->
        receive do
          :go -> send(parent, {:lookup, DBCleaner.lookup()})
        end
      end)

    assert {:ok, ^child} = DBCleaner.allow(self(), child)
    send(child, :go)
    assert_receive {:lookup, {:ok, ^conn}}, 1000
  end

  test "shared mode resolves any process to the shared owner's connection" do
    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :shared)
    parent = self()
    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, {:ok, ^conn}}, 1000
  end

  test "allow/2 fails when the owner has no connection" do
    other = spawn(fn -> Process.sleep(50) end)
    assert {:error, :no_owner} = DBCleaner.allow(self(), other)
  end

  test "clean/0 checks the connection in and removes ownership" do
    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
    assert {:ok, ^conn} = DBCleaner.lookup()

    assert :ok = DBCleaner.clean()
    assert Enum.any?(FakeRepo.calls(), &match?({:checkin, ^conn}, &1))
    assert :error = DBCleaner.lookup()
  end

  test "clean/0 clears the shared marker so later lookups fall through" do
    DBCleaner.start(:sandbox, repo: FakeRepo, mode: :shared)
    DBCleaner.clean()

    parent = self()
    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, :error}, 1000
  end

  test "clean/0 without a prior start is a safe no-op" do
    assert :ok = DBCleaner.clean()
  end

  test "ensure_registry/2 is idempotent" do
    assert {:ok, pid} = DBCleaner.ensure_registry()
    assert {:ok, ^pid} = DBCleaner.ensure_registry()
  end

  test "clean/0 revokes allowances pointing at the cleaned owner" do
    DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    parent = self()

    child =
      spawn(fn ->
        receive do
          :go -> send(parent, {:lookup, DBCleaner.lookup()})
        end
      end)

    assert {:ok, ^child} = DBCleaner.allow(self(), child)
    assert :ok = DBCleaner.clean()

    send(child, :go)
    assert_receive {:lookup, :error}, 1000
  end

  test "an allowance does not survive clean/0 into the owner's next checkout" do
    DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    parent = self()

    child =
      spawn(fn ->
        receive do
          :go -> send(parent, {:lookup, DBCleaner.lookup()})
        end
      end)

    assert {:ok, ^child} = DBCleaner.allow(self(), child)
    assert :ok = DBCleaner.clean()

    # The same process checks out a fresh connection; the old allowance was
    # dropped, so the previously-allowed process must not reach the new one.
    assert {:ok, conn2} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    assert {:ok, ^conn2} = DBCleaner.lookup()

    send(child, :go)
    assert_receive {:lookup, :error}, 1000
  end

  test "an owner resolves to its own connection even when a shared owner exists" do
    parent = self()

    shared_owner =
      spawn(fn ->
        {:ok, shared_conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :shared)
        send(parent, {:shared_ready, shared_conn})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:shared_ready, shared_conn}, 1000

    assert {:ok, own_conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
    refute own_conn == shared_conn
    assert {:ok, ^own_conn} = DBCleaner.lookup()

    send(shared_owner, :stop)
  end

  test "an explicit allowance takes precedence over the global shared owner" do
    parent = self()

    shared_owner =
      spawn(fn ->
        {:ok, shared_conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :shared)
        send(parent, {:shared_ready, shared_conn})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:shared_ready, shared_conn}, 1000

    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    refute conn == shared_conn

    child =
      spawn(fn ->
        receive do
          :go -> send(parent, {:lookup, DBCleaner.lookup()})
        end
      end)

    assert {:ok, ^child} = DBCleaner.allow(self(), child)
    send(child, :go)
    assert_receive {:lookup, {:ok, ^conn}}, 1000

    send(shared_owner, :stop)
  end

  test "lookup/1 resolves the connection of an explicitly given pid" do
    parent = self()

    child =
      spawn(fn ->
        {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
        send(parent, {:ready, conn})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:ready, child_conn}, 1000

    assert {:ok, ^child_conn} = DBCleaner.lookup(child)
    assert :error = DBCleaner.lookup(self())

    send(child, :stop)
  end

  test "a second clean/0 after a successful clean does not check the connection in twice" do
    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)

    assert :ok = DBCleaner.clean()
    assert :ok = DBCleaner.clean()

    checkins = Enum.filter(FakeRepo.calls(), &match?({:checkin, ^conn}, &1))
    assert length(checkins) == 1
  end

  test "mode: :manual never marks the owner as the global shared owner" do
    DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    parent = self()

    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, :error}, 1000
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
