  def get(name) do
    case :ets.select(@table, [{{{name, :"$1"}, :"$2"}, [], [:"$2"]}]) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end