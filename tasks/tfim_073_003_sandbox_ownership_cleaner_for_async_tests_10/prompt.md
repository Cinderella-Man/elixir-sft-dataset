# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DBCleaner do
  @moduledoc """
  Ecto-Sandbox-style ownership model that lets asynchronous integration tests
  share sandboxed connections across processes.

  Per-process state (which connection *this* process checked out) lives in the
  process dictionary. The cross-process ownership map lives in a single named
  Agent registry shaped as:

      %{owners: %{pid => conn}, allow: %{allowed_pid => owner_pid}, shared: pid | nil}

  `lookup/1` resolves a process to a connection by checking, in order:
  direct ownership, explicit allowance, then the global shared owner.
  """

  @registry :dbcleaner_ownership_registry
  @state_key {__MODULE__, :state}

  @doc "Start or return the running ownership registry. Idempotent."
  @spec ensure_registry() :: {:ok, pid()}
  def ensure_registry do
    case Process.whereis(@registry) do
      nil ->
        Agent.start_link(fn -> %{owners: %{}, allow: %{}, shared: nil} end, name: @registry)

      pid ->
        {:ok, pid}
    end
  end

  @spec start(:sandbox, keyword()) :: {:ok, reference()} | {:error, term()}
  def start(strategy, opts \\ [])

  def start(:sandbox, opts) do
    repo = fetch_repo!(opts)
    mode = Keyword.get(opts, :mode, :manual)
    ensure_registry()

    owner = self()
    conn = repo.checkout()

    Agent.update(@registry, fn s ->
      s2 = put_in(s.owners[owner], conn)
      if mode == :shared, do: %{s2 | shared: owner}, else: s2
    end)

    put_state(%{repo: repo, owner: owner, conn: conn, mode: mode})
    {:ok, conn}
  end

  def start(unknown, _opts) do
    {:error, "unknown strategy #{inspect(unknown)}. Expected :sandbox"}
  end

  @doc "Grant `allowed` access to `owner`'s connection."
  @spec allow(pid(), pid()) :: {:ok, pid()} | {:error, :no_owner}
  def allow(owner, allowed) when is_pid(owner) and is_pid(allowed) do
    ensure_registry()

    has_owner? = Agent.get(@registry, fn s -> Map.has_key?(s.owners, owner) end)

    if has_owner? do
      Agent.update(@registry, fn s -> put_in(s.allow[allowed], owner) end)
      {:ok, allowed}
    else
      {:error, :no_owner}
    end
  end

  @doc "Resolve which connection serves `pid`."
  @spec lookup(pid()) :: {:ok, reference()} | :error
  def lookup(pid \\ self()) do
    ensure_registry()

    Agent.get(@registry, fn s ->
      owner = Map.get(s.allow, pid)

      cond do
        Map.has_key?(s.owners, pid) ->
          {:ok, s.owners[pid]}

        owner != nil and Map.has_key?(s.owners, owner) ->
          {:ok, s.owners[owner]}

        s.shared != nil and Map.has_key?(s.owners, s.shared) ->
          {:ok, s.owners[s.shared]}

        true ->
          :error
      end
    end)
  end

  @doc "Check the connection in and remove this owner from the registry."
  @spec clean() :: :ok
  def clean do
    case get_state() do
      nil ->
        :ok

      %{repo: repo, owner: owner, conn: conn} ->
        try do
          repo.checkin(conn)
        rescue
          _ -> :ok
        end

        Agent.update(@registry, fn s ->
          owners = Map.delete(s.owners, owner)

          allow =
            s.allow
            |> Enum.reject(fn {_allowed, o} -> o == owner end)
            |> Map.new()

          shared = if s.shared == owner, do: nil, else: s.shared
          %{owners: owners, allow: allow, shared: shared}
        end)

        clear_state()
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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

  defp put_state(state), do: Process.put(@state_key, state)
  defp get_state, do: Process.get(@state_key)
  defp clear_state, do: Process.delete(@state_key)
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
end
```
