  defp fresh_state(capacity) do
    %{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      read: 0,
      write: 0,
      size: 0
    }
  end