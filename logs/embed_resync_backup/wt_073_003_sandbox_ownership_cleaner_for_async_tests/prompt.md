# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir module called `DBCleaner` that provides an Ecto-Sandbox-style **ownership** model so that *asynchronous* integration tests can safely share sandboxed database connections across multiple processes.

The base transaction cleaner only works for `async: false` because all interaction must happen on the one process that owns the checked-out connection. I want the connection-ownership machinery that makes shared/allowed connections possible, tracked in a small named registry.

I need this public API:

- `DBCleaner.ensure_registry()` — start (or return the already-running) named ownership registry Agent. Idempotent. Returns `{:ok, pid}`.

- `DBCleaner.start(:sandbox, opts \\ [])` — called in `setup`. `opts` must include `:repo` (an Ecto repo module) and may include `:mode` which is `:manual` (default) or `:shared`. Check out a connection for the calling process via `repo.checkout/0` (returns a connection reference), register the caller as the **owner** of that connection, and in `:shared` mode also mark this owner as the global shared owner so any process resolves to it. Store per-process state in the process dictionary. Returns `{:ok, conn_ref}`.

- `DBCleaner.allow(owner_pid, allowed_pid)` — grant `allowed_pid` access to `owner_pid`'s connection (manual explicit-allowance mode). Returns `{:ok, allowed_pid}`, or `{:error, :no_owner}` if `owner_pid` doesn't currently own a connection.

- `DBCleaner.lookup(pid \\ self())` — resolve which connection serves `pid`, checking in order: is `pid` itself an owner, has `pid` been explicitly allowed onto an owner, or is there a global shared owner. Returns `{:ok, conn_ref}` or `:error`.

- `DBCleaner.clean()` — called in `on_exit`. Check the connection back in via `repo.checkin/1`, and remove this owner from the registry along with any allowances pointing at it and the shared marker if it was the shared owner. Safe no-op if `start/2` was never called.

Keep it self-contained in one file (no dependencies beyond Ecto). Per-process state goes in the process dictionary; the cross-process ownership map lives in a single named Agent. Model the registry state as `%{owners: %{pid => conn}, allow: %{allowed_pid => owner_pid}, shared: pid | nil}`.

Give me the complete module in a single file.

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
  @spec ensure_registry() :: {:ok, pid()} | {:error, term()}
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
