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
end
