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