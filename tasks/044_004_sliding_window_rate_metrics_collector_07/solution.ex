  @doc "Returns the all-time total number of events recorded for `name`."
  @spec count(term()) :: number()
  def count(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [], [:"$2"]}])
    |> Enum.sum()
  end