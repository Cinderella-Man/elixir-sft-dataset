  @spec fire_notify((service_name(), term() -> any()) | nil, service_name(), term()) :: any()
  defp fire_notify(nil, _name, _reason), do: :ok
  defp fire_notify(notify_fn, name, reason), do: notify_fn.(name, reason)