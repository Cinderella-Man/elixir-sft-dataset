  defmacro assert_has_keys(map, keys) do
    quote bind_quoted: [map: map, keys: keys] do
      key_list = List.wrap(keys)
      missing = Enum.reject(key_list, fn k -> Map.has_key?(map, k) end)

      unless missing == [] do
        ExUnit.Assertions.flunk("""
        assert_has_keys failed

          missing keys  : #{inspect(missing)}
          expected keys : #{inspect(key_list)}
          present keys  : #{inspect(Map.keys(map))}
        """)
      end
    end
  end