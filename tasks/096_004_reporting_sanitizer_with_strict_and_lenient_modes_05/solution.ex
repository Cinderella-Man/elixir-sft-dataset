  @spec finalize(:lenient | :strict, String.t(), [atom()]) :: result()
  defp finalize(_mode, cleaned, []), do: {:ok, cleaned, []}
  defp finalize(:lenient, cleaned, violations), do: {:ok, cleaned, violations}
  defp finalize(:strict, _cleaned, violations), do: {:error, violations}