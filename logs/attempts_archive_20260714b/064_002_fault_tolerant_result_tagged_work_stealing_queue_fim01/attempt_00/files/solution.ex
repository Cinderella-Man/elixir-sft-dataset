  # Wrap a single item's processing so raise/throw/exit become tagged results.
  @spec safe_apply((any() -> any()), any()) :: tagged_result()
  defp safe_apply(process_fn, item) do
    try do
      {:ok, process_fn.(item)}
    rescue
      e -> {:error, %{kind: :error, reason: Exception.message(e)}}
    catch
      :throw, value -> {:error, %{kind: :throw, reason: value}}
      :exit, reason -> {:error, %{kind: :exit, reason: reason}}
    end
  end