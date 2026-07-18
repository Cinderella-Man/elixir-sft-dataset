  defp safe_execute({mod, fun, args}) do
    try do
      apply(mod, fun, args)
    rescue
      _ -> :crashed
    catch
      _, _ -> :crashed
    end
  end