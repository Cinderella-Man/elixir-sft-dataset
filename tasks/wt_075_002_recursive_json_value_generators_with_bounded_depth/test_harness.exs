defmodule JsonGeneratorsTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp depth(v) when is_list(v) do
    1 + Enum.reduce(v, 0, fn e, acc -> max(acc, depth(e)) end)
  end

  defp depth(v) when is_map(v) do
    1 + Enum.reduce(Map.values(v), 0, fn e, acc -> max(acc, depth(e)) end)
  end

  defp depth(_scalar), do: 0

  defp scalar?(v) do
    is_nil(v) or is_boolean(v) or is_integer(v) or is_binary(v)
  end

  # -------------------------------------------------------
  # JsonGenerators.scalar/0
  # -------------------------------------------------------

  describe "JsonGenerators.scalar/0" do
    property "always produces a JSON scalar of depth 0" do
      check all(v <- JsonGenerators.scalar()) do
        assert scalar?(v)
        assert depth(v) == 0
      end
    end

    property "strings are alphanumeric and at most 8 chars" do
      check all(v <- JsonGenerators.scalar()) do
        if is_binary(v) do
          assert String.length(v) <= 8
          assert v == "" or String.match?(v, ~r/^[a-zA-Z0-9]+$/)
        end
      end
    end

    property "produces diverse scalar kinds across many samples" do
      kinds =
        Enum.map(1..400, fn _ ->
          [v] = Enum.take(JsonGenerators.scalar(), 1)

          cond do
            is_nil(v) -> :null
            is_boolean(v) -> :bool
            is_integer(v) -> :int
            is_binary(v) -> :string
          end
        end)

      assert :null in kinds
      assert :bool in kinds
      assert :int in kinds
      assert :string in kinds
    end
  end

  # -------------------------------------------------------
  # JsonGenerators.array/2
  # -------------------------------------------------------

  describe "JsonGenerators.array/2" do
    property "produces lists within the length bound" do
      check all(list <- JsonGenerators.array(JsonGenerators.scalar(), 5)) do
        assert is_list(list)
        assert length(list) <= 5
      end
    end

    property "all elements come from the inner generator" do
      check all(list <- JsonGenerators.array(StreamData.integer(), 6)) do
        assert Enum.all?(list, &is_integer/1)
      end
    end

    property "produces empty and non-empty lists across samples" do
      lengths =
        Enum.map(1..300, fn _ ->
          [list] = Enum.take(JsonGenerators.array(JsonGenerators.scalar(), 5), 1)
          length(list)
        end)

      assert Enum.min(lengths) == 0
      assert Enum.max(lengths) > 0
    end
  end

  # -------------------------------------------------------
  # JsonGenerators.object/2
  # -------------------------------------------------------

  describe "JsonGenerators.object/2" do
    property "produces maps within the size bound" do
      check all(obj <- JsonGenerators.object(JsonGenerators.scalar(), 5)) do
        assert is_map(obj)
        assert map_size(obj) <= 5
      end
    end

    property "all keys are non-empty alphanumeric strings" do
      check all(obj <- JsonGenerators.object(StreamData.integer(), 5)) do
        for {k, _v} <- obj do
          assert is_binary(k)
          assert k != ""
          assert String.match?(k, ~r/^[a-zA-Z0-9]+$/)
        end
      end
    end

    property "all values come from the inner generator" do
      check all(obj <- JsonGenerators.object(StreamData.boolean(), 5)) do
        assert Enum.all?(Map.values(obj), &is_boolean/1)
      end
    end
  end

  # -------------------------------------------------------
  # JsonGenerators.value/1
  # -------------------------------------------------------

  describe "JsonGenerators.value/1" do
    property "value(0) is always a scalar" do
      check all(v <- JsonGenerators.value(0)) do
        assert scalar?(v)
        assert depth(v) == 0
      end
    end

    property "negative depth is treated as a scalar" do
      check all(v <- JsonGenerators.value(-3)) do
        assert scalar?(v)
      end
    end

    property "value(2) never exceeds depth 2" do
      check all(v <- JsonGenerators.value(2)) do
        assert depth(v) <= 2
      end
    end

    property "value(4) never exceeds depth 4" do
      check all(v <- JsonGenerators.value(4)) do
        assert depth(v) <= 4
      end
    end

    property "every produced value is JSON-shaped (scalar, list, or map)" do
      check all(v <- JsonGenerators.value(3)) do
        assert scalar?(v) or is_list(v) or is_map(v)
      end
    end

    property "produces scalars, arrays, and objects across many samples" do
      kinds =
        Enum.map(1..500, fn _ ->
          [v] = Enum.take(JsonGenerators.value(3), 1)

          cond do
            is_list(v) -> :array
            is_map(v) -> :object
            true -> :scalar
          end
        end)

      assert :scalar in kinds
      assert :array in kinds
      assert :object in kinds
    end
  end

  # -------------------------------------------------------
  # Composability
  # -------------------------------------------------------

  describe "composability with StreamData" do
    property "value can be nested inside list_of" do
      check all(list <- StreamData.list_of(JsonGenerators.value(2), length: 3)) do
        assert length(list) == 3
        assert Enum.all?(list, fn v -> depth(v) <= 2 end)
      end
    end

    property "value can be filtered to only containers" do
      gen = StreamData.filter(JsonGenerators.value(3), fn v -> is_list(v) or is_map(v) end)

      check all(v <- gen) do
        assert is_list(v) or is_map(v)
        assert depth(v) <= 3
      end
    end
  end

  # -------------------------------------------------------
  # Zero-length bounds and boundary attainment (seeded)
  # -------------------------------------------------------

  test "array/2 accepts max_length 0 and then only produces the empty list" do
    lists =
      Enum.map(1..50, fn seed ->
        [list] =
          JsonGenerators.array(JsonGenerators.scalar(), 0)
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        list
      end)

    assert Enum.all?(lists, &(&1 == []))
  end

  test "object/2 accepts max_length 0 and then only produces the empty map" do
    maps =
      Enum.map(1..50, fn seed ->
        [obj] =
          JsonGenerators.object(JsonGenerators.scalar(), 0)
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        obj
      end)

    assert Enum.all?(maps, &(&1 == %{}))
  end

  test "scalar strings attain the documented 8-char maximum across seeded samples" do
    lengths =
      Enum.map(1..300, fn seed ->
        [v] =
          JsonGenerators.scalar()
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        if is_binary(v), do: String.length(v), else: -1
      end)

    assert Enum.max(lengths) == 8
  end

  test "value(2) attains the full depth of 2 across seeded samples" do
    depths =
      Enum.map(1..300, fn seed ->
        [v] =
          JsonGenerators.value(2)
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        depth(v)
      end)

    assert Enum.max(depths) == 2
  end
end
