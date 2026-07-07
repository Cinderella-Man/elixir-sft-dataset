  defp effect(record, :approve, %{approver: a}), do: Map.put(record, :approved_by, a)

  defp effect(record, :reject, %{reason: r}), do: Map.put(record, :rejection_reason, r)

  defp effect(record, :complete, _payload), do: Map.put(record, :completed, true)

  defp effect(record, :cancel, %{reason: r}) when is_binary(r),
    do: Map.put(record, :cancelled_reason, r)

  defp effect(record, _event, _payload), do: record