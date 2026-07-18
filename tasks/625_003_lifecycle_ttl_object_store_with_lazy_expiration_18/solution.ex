  @spec now_ms() :: integer()
  defp now_ms, do: System.monotonic_time(:millisecond)