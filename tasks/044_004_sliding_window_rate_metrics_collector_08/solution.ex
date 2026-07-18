  @doc "Deletes every bucket for `name`."
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.match_delete(@table, {{name, :_}, :_})
    :ok
  end