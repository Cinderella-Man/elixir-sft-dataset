# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule DBCleaner do
  @registry :dbcleaner_ownership_registry
  @state_key {__MODULE__, :state}

  def ensure_registry do
    case Process.whereis(@registry) do
      nil ->
        Agent.start_link(fn -> %{owners: %{}, allow: %{}, shared: nil} end, name: @registry)

      pid ->
        {:ok, pid}
    end
  end

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
