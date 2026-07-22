  defp run_action(step, context, attempt) do
    case step.action.(context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if attempt < step.max_attempts do
          run_action(step, context, attempt + 1)
        else
          {:error, reason, attempt}
        end
    end
  end