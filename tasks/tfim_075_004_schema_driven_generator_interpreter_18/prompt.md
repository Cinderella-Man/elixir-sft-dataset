# Fill in the middle: implement the blanked property

Below is a module and its ExUnit test harness with the body of ONE `property` removed
(marked `# TODO`). The property's name states what it must verify. Implement just that one
property so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule SchemaGenerators do
  @moduledoc """
  Turns a declarative schema term into a `StreamData` generator at runtime, for
  use with property-based testing via `StreamData` and `ExUnitProperties`.

  Rather than hand-writing one generator per type, `from_schema/1` is a small
  recursive interpreter: it walks a schema value and returns a `%StreamData{}`
  generator whose outputs conform to that schema. Nested schemas produce nested
  generators, and every constraint is baked into the returned generator so
  consumers never filter.

  ## Schema grammar

      :integer
      {:integer, min, max}
      :boolean
      :string
      {:string, min_len, max_len}
      {:enum, [value, ...]}
      {:list, schema}
      {:list, schema, opts}          # opts: [min: n, max: n]
      {:map, %{key => schema}}
      {:optional, schema}
      {:one_of, [schema, ...]}

  ## Usage

      use ExUnitProperties

      property "conforms to the schema" do
        gen = SchemaGenerators.from_schema({:map, %{id: {:integer, 1, 100}}})

        check all value <- gen do
          assert value.id in 1..100
        end
      end
  """

  alias StreamData, as: SD

  @doc """
  Interprets `schema` and returns a `StreamData` generator producing conforming
  values. Recurses through nested schemas.
  """
  @spec from_schema(term()) :: StreamData.t(term())
  def from_schema(:integer), do: SD.integer()

  def from_schema(:boolean), do: SD.boolean()

  def from_schema(:string), do: SD.string(:alphanumeric)

  def from_schema({:integer, min, max})
      when is_integer(min) and is_integer(max) and min <= max do
    SD.integer(min..max)
  end

  def from_schema({:string, min_len, max_len})
      when is_integer(min_len) and is_integer(max_len) and min_len >= 0 and min_len <= max_len do
    SD.string(:alphanumeric, min_length: min_len, max_length: max_len)
  end

  def from_schema({:enum, values}) when is_list(values) and values != [] do
    SD.member_of(values)
  end

  def from_schema({:list, inner}) do
    SD.list_of(from_schema(inner))
  end

  def from_schema({:list, inner, opts}) when is_list(opts) do
    min = Keyword.get(opts, :min, 0)
    max = Keyword.get(opts, :max, 10)

    SD.bind(SD.integer(min..max), fn len ->
      SD.list_of(from_schema(inner), length: len)
    end)
  end

  def from_schema({:map, schema_map}) when is_map(schema_map) do
    generators = Map.new(schema_map, fn {key, schema} -> {key, from_schema(schema)} end)
    SD.fixed_map(generators)
  end

  def from_schema({:optional, inner}) do
    SD.one_of([SD.constant(nil), from_schema(inner)])
  end

  def from_schema({:one_of, schemas}) when is_list(schemas) and schemas != [] do
    SD.one_of(Enum.map(schemas, &from_schema/1))
  end
end
```

## Test harness — implement the `# TODO` property

```elixir
defmodule SchemaGeneratorsTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  # -------------------------------------------------------
  # Scalar schemas
  # -------------------------------------------------------

  describe "scalar schemas" do
    property ":integer produces integers" do
      check all(v <- SchemaGenerators.from_schema(:integer)) do
        assert is_integer(v)
      end
    end

    property "{:integer, min, max} stays within bounds" do
      check all(v <- SchemaGenerators.from_schema({:integer, 10, 20})) do
        assert is_integer(v)
        assert v >= 10 and v <= 20
      end
    end

    property ":boolean produces booleans" do
      check all(v <- SchemaGenerators.from_schema(:boolean)) do
        assert is_boolean(v)
      end
    end

    property ":string produces alphanumeric strings" do
      check all(v <- SchemaGenerators.from_schema(:string)) do
        assert is_binary(v)
        assert v == "" or String.match?(v, ~r/^[a-zA-Z0-9]+$/)
      end
    end

    property "{:string, min, max} respects the length bounds" do
      check all(v <- SchemaGenerators.from_schema({:string, 3, 5})) do
        assert is_binary(v)
        assert String.length(v) >= 3 and String.length(v) <= 5
      end
    end

    property "{:enum, values} only produces listed values" do
      values = [:red, :green, :blue]

      check all(v <- SchemaGenerators.from_schema({:enum, values})) do
        assert v in values
      end
    end
  end

  # -------------------------------------------------------
  # List schemas
  # -------------------------------------------------------

  describe "list schemas" do
    property "{:list, schema} produces lists of conforming values" do
      check all(v <- SchemaGenerators.from_schema({:list, :boolean})) do
        assert is_list(v)
        assert Enum.all?(v, &is_boolean/1)
      end
    end

    property "{:list, schema, opts} respects length bounds" do
      schema = {:list, {:integer, 0, 9}, [min: 2, max: 4]}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert is_list(v)
        assert length(v) >= 2 and length(v) <= 4
        assert Enum.all?(v, fn n -> n >= 0 and n <= 9 end)
      end
    end
  end

  # -------------------------------------------------------
  # Map schemas
  # -------------------------------------------------------

  describe "map schemas" do
    property "{:map, schema_map} produces fixed-shape maps" do
      schema =
        {:map,
         %{
           id: {:integer, 1, 100},
           active: :boolean,
           name: {:string, 1, 6}
         }}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert is_map(v)
        assert Map.keys(v) |> Enum.sort() == [:active, :id, :name]
        assert v.id >= 1 and v.id <= 100
        assert is_boolean(v.active)
        assert String.length(v.name) >= 1 and String.length(v.name) <= 6
      end
    end

    property "nested list-of-maps schema produces correctly nested values" do
      schema =
        {:list,
         {:map,
          %{
            tag: {:enum, ["x", "y", "z"]},
            score: {:integer, 0, 10}
          }}, [min: 0, max: 3]}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert is_list(v)
        assert length(v) <= 3

        for row <- v do
          assert row.tag in ["x", "y", "z"]
          assert row.score >= 0 and row.score <= 10
        end
      end
    end
  end

  # -------------------------------------------------------
  # optional / one_of
  # -------------------------------------------------------

  describe "optional and one_of schemas" do
    property "{:optional, schema} produces nil or a conforming value" do
      check all(v <- SchemaGenerators.from_schema({:optional, {:integer, 1, 5}})) do
        assert is_nil(v) or (is_integer(v) and v >= 1 and v <= 5)
      end
    end

    property "{:optional, schema} produces both nil and values across samples" do
      results =
        Enum.map(1..300, fn _ ->
          [v] = Enum.take(SchemaGenerators.from_schema({:optional, :integer}), 1)
          is_nil(v)
        end)

      assert true in results
      assert false in results
    end

    property "{:one_of, schemas} produces a value from one branch" do
      schema = {:one_of, [{:integer, 0, 5}, :boolean]}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert (is_integer(v) and v >= 0 and v <= 5) or is_boolean(v)
      end
    end

    property "{:one_of, schemas} exercises multiple branches across samples" do
      schema = {:one_of, [:integer, :boolean]}

      kinds =
        Enum.map(1..300, fn _ ->
          [v] = Enum.take(SchemaGenerators.from_schema(schema), 1)
          if is_boolean(v), do: :bool, else: :int
        end)

      assert :bool in kinds
      assert :int in kinds
    end
  end

  # -------------------------------------------------------
  # Composability
  # -------------------------------------------------------

  describe "composability with StreamData" do
    property "a schema generator can be nested in list_of" do
      gen = StreamData.list_of(SchemaGenerators.from_schema({:integer, 1, 3}), length: 4)

      check all(v <- gen) do
        assert length(v) == 4
        assert Enum.all?(v, fn n -> n in [1, 2, 3] end)
      end
    end

    property "a schema generator can be mapped" do
      gen = StreamData.map(SchemaGenerators.from_schema({:integer, 1, 10}), &(&1 * 2))

      check all(v <- gen) do
        assert rem(v, 2) == 0
        assert v >= 2 and v <= 20
      end
    end
  end

  # -------------------------------------------------------
  # Boundary bounds and defaults
  # -------------------------------------------------------

  describe "boundary bounds and defaults" do
    property "{:integer, min, max} supports min == max" do
      # TODO
    end

    property "{:string, min_len, max_len} supports zero-length bounds" do
      check all(v <- SchemaGenerators.from_schema({:string, 0, 0})) do
        assert v == ""
      end
    end

    property "{:list, schema, opts} defaults length bounds to 0..10" do
      lengths =
        SchemaGenerators.from_schema({:list, :boolean, []})
        |> Enum.take(300)
        |> Enum.map(&length/1)

      assert Enum.all?(lengths, fn len -> len >= 0 and len <= 10 end)
      assert 0 in lengths
      assert 10 in lengths
    end
  end

  test "{:list, schema, opts} applies each documented default independently" do
    min_only =
      SchemaGenerators.from_schema({:list, :boolean, [min: 3]})
      |> Enum.take(300)
      |> Enum.map(&length/1)

    assert Enum.all?(min_only, fn len -> len >= 3 and len <= 10 end)
    assert 3 in min_only
    assert 10 in min_only

    max_only =
      SchemaGenerators.from_schema({:list, :boolean, [max: 2]})
      |> Enum.take(300)
      |> Enum.map(&length/1)

    assert Enum.all?(max_only, fn len -> len >= 0 and len <= 2 end)
    assert 0 in max_only
    assert 2 in max_only
  end

  test "from_schema/1 returns a %StreamData{} struct for every schema form" do
    schemas = [
      :integer,
      {:integer, 1, 2},
      :boolean,
      :string,
      {:string, 0, 2},
      {:enum, [:a, :b]},
      {:list, :boolean},
      {:list, :boolean, []},
      {:map, %{a: :integer}},
      {:optional, :integer},
      {:one_of, [:integer, :boolean]}
    ]

    for schema <- schemas do
      assert %StreamData{} = SchemaGenerators.from_schema(schema)
    end
  end

  test "map schema with optional list-valued field nests generators correctly" do
    schema =
      {:map,
       %{
         tags: {:optional, {:list, {:string, 1, 3}, [min: 1, max: 2]}},
         n: {:integer, 0, 3}
       }}

    values = SchemaGenerators.from_schema(schema) |> Enum.take(300)

    for v <- values do
      assert Map.keys(v) |> Enum.sort() == [:n, :tags]
      assert v.n >= 0 and v.n <= 3

      case v.tags do
        nil ->
          :ok

        list ->
          assert is_list(list)
          assert length(list) >= 1 and length(list) <= 2

          assert Enum.all?(list, fn s ->
                   is_binary(s) and String.length(s) >= 1 and String.length(s) <= 3
                 end)
      end
    end

    assert Enum.any?(values, fn v -> is_nil(v.tags) end)
    assert Enum.any?(values, fn v -> is_list(v.tags) end)
  end
end
```
