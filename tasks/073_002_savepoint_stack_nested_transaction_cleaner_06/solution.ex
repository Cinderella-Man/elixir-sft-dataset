  @doc "Roll back the outer transaction, discarding all writes."
  @spec clean() :: :ok | {:error, term()}
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