# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule DBCleaner do
  @state_key {__MODULE__, :state}
  @valid_identifier ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  def start(strategy, opts \\ [])

  def start(:savepoint, opts) do
    repo = fetch_repo!(opts)

    try do
      {:ok, _ref} = repo.begin_transaction()
      put_state(%{repo: repo, stack: []})
      {:ok, :savepoint}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def start(unknown, _opts) do
    {:error, "unknown strategy #{inspect(unknown)}. Expected :savepoint"}
  end

  def savepoint(name) when is_binary(name) do
    if Regex.match?(@valid_identifier, name) do
      case get_state() do
        nil ->
          {:error, :not_started}

        %{repo: repo, stack: stack} = state ->
          try do
            repo.query!(repo, "SAVEPOINT #{name}", [])
            put_state(%{state | stack: [name | stack]})
            {:ok, name}
          rescue
            e -> {:error, Exception.message(e)}
          end
      end
    else
      {:error, {:invalid_name, name}}
    end
  end

  def savepoint(other), do: {:error, {:invalid_name, other}}

  def rollback_to(name) when is_binary(name) do
    case get_state() do
      nil ->
        {:error, :not_started}

      %{repo: repo, stack: stack} = state ->
        if name in stack do
          try do
            repo.query!(repo, "ROLLBACK TO SAVEPOINT #{name}", [])
            new_stack = Enum.drop_while(stack, fn n -> n != name end)
            put_state(%{state | stack: new_stack})
            {:ok, name}
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          {:error, {:no_such_savepoint, name}}
        end
    end
  end

  def release(name) when is_binary(name) do
    case get_state() do
      nil ->
        {:error, :not_started}

      %{repo: repo, stack: stack} = state ->
        if name in stack do
          try do
            repo.query!(repo, "RELEASE SAVEPOINT #{name}", [])
            new_stack = stack |> Enum.drop_while(fn n -> n != name end) |> tl()
            put_state(%{state | stack: new_stack})
            {:ok, name}
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          {:error, {:no_such_savepoint, name}}
        end
    end
  end

  def active_savepoints do
    case get_state() do
      nil -> []
      %{stack: stack} -> Enum.reverse(stack)
    end
  end

  def clean do
    case get_state() do
      nil ->
        :ok

      %{repo: repo} ->
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
