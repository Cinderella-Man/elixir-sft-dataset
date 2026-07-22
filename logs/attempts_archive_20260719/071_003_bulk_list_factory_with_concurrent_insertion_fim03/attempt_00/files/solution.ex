def insert_list(count, name, overrides) when is_integer(count) and count >= 0 do
  1..count//1
  |> Enum.map(fn _ -> Task.async(fn -> insert(name, overrides) end) end)
  |> Task.await_many()
end