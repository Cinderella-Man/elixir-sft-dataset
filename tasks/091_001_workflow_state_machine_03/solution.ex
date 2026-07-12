  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true
  defp guard(:submit, _record), do: false

  defp guard(:approve, %{approved_by: approved_by})
       when is_binary(approved_by) and approved_by != "",
       do: true

  defp guard(:approve, _record), do: false

  # All other transitions have no guard and always pass.
  defp guard(_event, _record), do: true
