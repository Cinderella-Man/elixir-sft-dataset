  @doc "Resets every series under `name` to `0`."
  @spec reset(term()) :: :ok
  def reset(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :_}, [], [:"$1"]}])
    |> Enum.each(fn norm -> :ets.insert(@table, {{name, norm}, 0}) end)

    :ok
  end