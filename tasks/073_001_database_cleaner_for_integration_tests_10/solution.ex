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