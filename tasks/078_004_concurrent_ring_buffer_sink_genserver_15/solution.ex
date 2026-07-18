  defp do_peek_oldest(%{size: 0}), do: :error

  defp do_peek_oldest(%{store: store, read: read}) do
    {:ok, :erlang.element(read + 1, store)}
  end