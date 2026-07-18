  @spec now(keyword()) :: integer()
  defp now(opts) do
    case Keyword.get(opts, :clock) do
      fun when is_function(fun, 0) -> fun.()
      _ -> System.os_time(:second)
    end
  end