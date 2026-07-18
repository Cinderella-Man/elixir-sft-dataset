  @spec safe((context() -> term()), context()) :: action_result()
  defp safe(action, context) do
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end