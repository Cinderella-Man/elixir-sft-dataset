# Runs the mfa inside a try/rescue/catch and classifies the outcome.
defp safe_execute({mod, fun, args}) do
  try do
    case apply(mod, fun, args) do
      :ok -> :success
      {:ok, _} -> :success
      _ -> :failure
    end
  rescue
    _ -> :failure
  catch
    _, _ -> :failure
  end
end
