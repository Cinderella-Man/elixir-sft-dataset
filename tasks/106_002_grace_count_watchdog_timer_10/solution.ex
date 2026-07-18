  defp safe_invoke(fun, name, misses) do
    fun.(name, misses)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end