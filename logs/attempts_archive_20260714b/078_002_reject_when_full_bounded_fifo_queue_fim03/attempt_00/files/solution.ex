def push(%__MODULE__{size: size, capacity: capacity}, _item) when size == capacity do
  {:error, :full}
end

def push(%__MODULE__{capacity: cap, store: store, write: write, size: size} = buf, item) do
  new_store = :erlang.setelement(write + 1, store, item)
  {:ok, %{buf | store: new_store, write: rem(write + 1, cap), size: size + 1}}
end