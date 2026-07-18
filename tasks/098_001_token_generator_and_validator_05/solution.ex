  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      fun when is_function(fun, 0) -> fun.()
    end
  end