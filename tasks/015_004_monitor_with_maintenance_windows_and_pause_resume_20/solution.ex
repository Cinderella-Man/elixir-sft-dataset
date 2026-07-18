  @spec fire_notify(
          (service_name(), atom(), term() -> any()) | nil,
          service_name(),
          atom(),
          term()
        ) :: any()
  defp fire_notify(nil, _name, _event, _detail), do: :ok
  defp fire_notify(notify_fn, name, event, detail), do: notify_fn.(name, event, detail)