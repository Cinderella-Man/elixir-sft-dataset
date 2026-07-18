# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule DBCleaner do
  @state_key {__MODULE__, :state}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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
