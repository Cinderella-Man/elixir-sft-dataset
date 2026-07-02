defp guard(:submit, %{items: items}, _payload) when is_list(items) and items != [], do: true
defp guard(:submit, _record, _payload), do: false

defp guard(:approve, _record, %{approver: a}) when is_binary(a) and a != "", do: true
defp guard(:approve, _record, _payload), do: false

defp guard(:reject, _record, %{reason: r}) when is_binary(r) and r != "", do: true
defp guard(:reject, _record, _payload), do: false

defp guard(_event, _record, _payload), do: true