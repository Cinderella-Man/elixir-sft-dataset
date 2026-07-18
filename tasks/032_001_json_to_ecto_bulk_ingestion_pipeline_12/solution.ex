  defp validate_conflict_opts([], _on_conflict, _target), do: :ok

  defp validate_conflict_opts([_ | _], :replace_all, []),
    do: {:error, :conflict_target_required}

  defp validate_conflict_opts(_records, _on_conflict, _target), do: :ok