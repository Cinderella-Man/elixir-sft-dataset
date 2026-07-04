  # Runs the action and normalises any unexpected return into an error.
  @spec safe_action((context() -> term()), context()) :: {:ok, term()} | {:error, term()}
  defp safe_action(action, context) do
    case action.(context) do
      {:ok, _} = ok       -> ok
      {:error, _} = error -> error
      other               -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end