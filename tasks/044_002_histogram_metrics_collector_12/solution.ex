  @doc """
  Erases all recorded data for `name`, so a later `get/1` returns `nil`.
  """
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.match_delete(@table, {{name, :count}, :_})
    :ets.match_delete(@table, {{name, :sum}, :_})
    :ets.match_delete(@table, {{name, :bucket, :_}, :_})
    :ok
  end