defp run_handler(handler, message) do
  case handler.(message) do
    :ok -> :success
    {:ok, _term} -> :success
    {:error, reason} -> {:failure, reason}
    other -> {:failure, {:unexpected_return, other}}
  end
rescue
  exception -> {:failure, {:handler_raised, exception}}
catch
  kind, value -> {:failure, {kind, value}}
end