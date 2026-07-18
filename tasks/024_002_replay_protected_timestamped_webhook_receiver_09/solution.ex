  defp current_time(opts) do
    case Keyword.get(opts, :now) do
      nil -> System.system_time(:second)
      fun when is_function(fun, 0) -> fun.()
      int when is_integer(int) -> int
    end
  end