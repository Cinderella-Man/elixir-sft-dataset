  defp execute([], value, meta_acc), do: {:ok, value, Enum.reverse(meta_acc)}

  defp execute([stage | rest], value, meta_acc) do
    case run_stage(stage, value) do
      {:ok, next_value, meta} -> execute(rest, next_value, [meta | meta_acc])
      {:error, name, reason} -> {:error, name, reason}
    end
  end