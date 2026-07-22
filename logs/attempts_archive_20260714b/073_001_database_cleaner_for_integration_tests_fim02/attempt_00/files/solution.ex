def start(strategy, opts \\ [])

def start(:transaction, opts) do
  repo = fetch_repo!(opts)

  try do
    {:ok, _ref} = repo.begin_transaction()
    put_state(%{strategy: :transaction, repo: repo})
    {:ok, :transaction}
  rescue
    e -> {:error, Exception.message(e)}
  end
end

def start(:truncation, opts) do
  repo   = fetch_repo!(opts)
  tables = Keyword.get(opts, :tables, [])

  validate_tables!(tables)

  put_state(%{strategy: :truncation, repo: repo, tables: tables})
  {:ok, :truncation}
end

def start(unknown, _opts) do
  {:error, "unknown strategy #{inspect(unknown)}. Expected :transaction or :truncation"}
end