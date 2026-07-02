defmodule MergeSchemaTest do
  use ExUnit.Case, async: false

  test "infer_string works end-to-end like the base task" do
    csv = """
    name,age,height,active,birth,created
    Alice,30,5.5,true,2020-01-15,2020-01-15T10:30:00
    Bob,25,6.0,false,1999-12-31,1999-12-31T08:00:00
    """

    assert MergeSchema.infer_string(csv) == %{
             "name" => :string,
             "age" => :integer,
             "height" => :float,
             "active" => :boolean,
             "birth" => :date,
             "created" => :datetime
           }
  end

  test "partial exposes the documented representation" do
    p = MergeSchema.partial("n\n1\n2\n")
    assert p.names == ["n"]
    assert p.ncols == 1
    assert p.categories == %{0 => MapSet.new([:integer])}
  end

  test "a header chunk merges with a headerless data chunk to promote the type" do
    p1 = MergeSchema.partial("n\n1\n2\n")
    p2 = MergeSchema.partial("3.5\n", headers: false)

    merged = MergeSchema.merge(p1, p2)
    assert merged.names == ["n"]
    assert merged.categories == %{0 => MapSet.new([:integer, :float])}
    assert MergeSchema.finalize(merged) == %{"n" => :float}
  end

  test "merge is commutative at the finalized level" do
    a = MergeSchema.partial("v\n1\nhello\n")
    b = MergeSchema.partial("2\nworld\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) ==
             MergeSchema.finalize(MergeSchema.merge(b, a))
  end

  test "merge is idempotent" do
    p = MergeSchema.partial("d\n2020-01-15\n03/25/2021\n")

    assert MergeSchema.merge(p, p) == p
    assert MergeSchema.finalize(MergeSchema.merge(p, p)) == MergeSchema.finalize(p)
  end

  test "merge is associative across three chunks" do
    a = MergeSchema.partial("val\n1\n")
    b = MergeSchema.partial("2\n", headers: false)
    c = MergeSchema.partial("3.5\n", headers: false)

    left = MergeSchema.merge(MergeSchema.merge(a, b), c)
    right = MergeSchema.merge(a, MergeSchema.merge(b, c))

    assert MergeSchema.finalize(left) == MergeSchema.finalize(right)
    assert MergeSchema.finalize(left) == %{"val" => :float}
  end

  test "positional chunks merge and finalize with generated names" do
    a = MergeSchema.partial("1,2.5\n", headers: false)
    b = MergeSchema.partial("3,4.5\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) == %{
             "column_1" => :integer,
             "column_2" => :float
           }
  end

  test "mixing incompatible categories across chunks resolves to string" do
    a = MergeSchema.partial("x\n2020-01-15\n")
    b = MergeSchema.partial("2020-01-15T10:00:00\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) == %{"x" => :string}
  end

  test "quoted values stay strings after merging" do
    a = MergeSchema.partial("code\n\"123\"\n")
    b = MergeSchema.partial("\"456\"\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) == %{"code" => :string}
  end

  test "header-only fragment yields all-string columns" do
    assert MergeSchema.infer_string("a,b,c\n") == %{
             "a" => :string,
             "b" => :string,
             "c" => :string
           }
  end

  test "ncols takes the max across ragged chunks" do
    a = MergeSchema.partial("1\n", headers: false)
    b = MergeSchema.partial("2,3,4\n", headers: false)

    merged = MergeSchema.merge(a, b)
    assert merged.ncols == 3

    assert MergeSchema.finalize(merged) == %{
             "column_1" => :integer,
             "column_2" => :integer,
             "column_3" => :integer
           }
  end
end