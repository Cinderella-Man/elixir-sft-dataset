  # Runs all compensations in order (which is already reverse-execution order)
  # and collects their results. Exceptions are caught and stored.
  @spec compensate_all([step()], context()) :: compensation_results()
  defp compensate_all(completed_steps, context) do
    Enum.map(completed_steps, fn %{name: name, compensate: compensate} ->
      result =
        try do
          compensate.(context)
        rescue
          exception -> {:exception, exception, __STACKTRACE__}
        catch
          kind, value -> {:caught, kind, value}
        end

      {name, result}
    end)
  end