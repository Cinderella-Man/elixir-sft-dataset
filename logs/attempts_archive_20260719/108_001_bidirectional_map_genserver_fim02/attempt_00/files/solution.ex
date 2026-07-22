def delete(name, key) do
  GenServer.call(name, {:delete, key})
end