def peek_newest(%__MODULE__{size: 0}), do: :error

def peek_newest(%__MODULE__{capacity: cap, store: store, write: write}) do
  newest_index = rem(write - 1 + cap, cap)
  {:ok, :erlang.element(newest_index + 1, store)}
end