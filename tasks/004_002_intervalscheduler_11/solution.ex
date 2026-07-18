  # Guard the scheduler against job crashes.  We ignore the return value —
  # interval jobs fire regardless of outcome.
  defp safe_execute({mod, fun, args}) do
    try do
      apply(mod, fun, args)
    rescue
      _ -> :crashed
    catch
      _, _ -> :crashed
    end
  end