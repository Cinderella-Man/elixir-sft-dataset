  defp do_peek_newest(%{size: 0}), do: :error

  defp do_peek_newest(%{capacity: cap, store: store, write: write}) do
    newest_index = rem(write - 1 + cap, cap)
    {:ok, :erlang.element(newest_index + 1, store)}
  end