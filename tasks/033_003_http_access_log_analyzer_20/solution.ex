  defp update_error_count(acc, status_code) when status_code >= 400 do
    %{acc | error_count: acc.error_count + 1}
  end

  defp update_error_count(acc, _status_code), do: acc