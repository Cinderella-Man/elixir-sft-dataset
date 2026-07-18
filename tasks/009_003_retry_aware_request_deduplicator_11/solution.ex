  defp reply_all(callers, result) do
    Enum.each(callers, &GenServer.reply(&1, result))
  end