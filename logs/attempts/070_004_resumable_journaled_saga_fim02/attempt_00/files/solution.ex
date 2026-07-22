  @spec run([step_entry()], [step_entry()], context(), journal()) :: run_result()
  defp run([], _completed, context, jrev), do: {:ok, context, Enum.reverse(jrev)}

  defp run([%{name: name, action: action} = step | rest], completed, context, jrev) do
    case safe(action, context) do
      {:ok, result} ->
        run(
          rest,
          [step | completed],
          Map.put(context, name, result),
          [{:completed, name, result} | jrev]
        )

      {:error, reason} ->
        {comp, jrev2} = compensate_all(completed, context, [{:failed, name, reason} | jrev])
        {:error, name, reason, comp, Enum.reverse(jrev2)}
    end
  end