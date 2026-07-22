def object(value_gen, max_length) when is_integer(max_length) and max_length >= 0 do
  key = SD.string(:alphanumeric, min_length: 1, max_length: 8)
  pair = SD.tuple({key, value_gen})

  SD.map(SD.list_of(pair, max_length: max_length), &Map.new/1)
end