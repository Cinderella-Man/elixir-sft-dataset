  @spec fire_notify((service_name(), float() -> any()) | nil, service_name(), float()) :: any()
  defp fire_notify(nil, _name, _rate), do: :ok
  defp fire_notify(notify_fn, name, rate), do: notify_fn.(name, rate)