defmodule StrictConfigMergerTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "non-strict merge lets override win and returns :ok" do
    base = %{host: "localhost", port: 4000}
    override = %{port: 9000}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override)
    assert merged == %{host: "localhost", port: 9000}
  end

  test "deep merge returns :ok" do
    base = %{db: %{host: "localhost", port: 5432, name: "prod"}}
    override = %{db: %{port: 5433}}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override)
    assert merged.db == %{host: "localhost", port: 5433, name: "prod"}
  end

  test "strict merge with matching types returns :ok" do
    base = %{port: 4000, name: "a"}
    override = %{port: 9000, name: "b"}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: true)
    assert merged == %{port: 9000, name: "b"}
  end

  # -------------------------------------------------------
  # Type mismatch (strict)
  # -------------------------------------------------------

  test "strict scalar type mismatch is a conflict" do
    base = %{port: 5432}
    override = %{port: "5433"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, strict: true)
    assert conflict.type == :type_mismatch
    assert conflict.path == [:port]
    assert conflict.base == 5432
    assert conflict.override == "5433"
  end

  test "strict structural mismatch (map vs scalar) is a conflict" do
    base = %{db: %{host: "localhost"}}
    override = %{db: "disabled"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, strict: true)
    assert conflict.type == :type_mismatch
    assert conflict.path == [:db]
  end

  test "non-strict type mismatch is NOT a conflict; override wins" do
    base = %{port: 5432}
    override = %{port: "5433"}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: false)
    assert merged.port == "5433"
  end

  test "two lists never count as a type mismatch even in strict mode" do
    base = %{tags: ["a"]}
    override = %{tags: ["b"]}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: true)
    assert merged.tags == ["b"]
  end

  # -------------------------------------------------------
  # Locked
  # -------------------------------------------------------

  test "locked violation is a conflict regardless of strict" do
    base = %{secret: "keep"}
    override = %{secret: "change"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, locked: [[:secret]])
    assert conflict.type == :locked_violation
    assert conflict.path == [:secret]
    assert conflict.base == "keep"
    assert conflict.override == "change"
  end

  test "locked path with identical override value is fine" do
    base = %{secret: "keep", other: 1}
    override = %{secret: "keep", other: 2}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, locked: [[:secret]])
    assert merged.secret == "keep"
    assert merged.other == 2
  end

  test "nested locked violation is detected" do
    base = %{db: %{password: "s3cr3t"}}
    override = %{db: %{password: "pwned"}}

    assert {:error, [conflict]} =
             StrictConfigMerger.merge(base, override, locked: [[:db, :password]])

    assert conflict.type == :locked_violation
    assert conflict.path == [:db, :password]
  end

  # -------------------------------------------------------
  # Required
  # -------------------------------------------------------

  test "missing required key is a conflict" do
    base = %{a: 1}
    override = %{}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, required: [[:b]])
    assert conflict.type == :missing_required
    assert conflict.path == [:b]
  end

  test "present required key passes" do
    base = %{a: %{b: 1}}
    override = %{}

    assert {:ok, _merged} = StrictConfigMerger.merge(base, override, required: [[:a, :b]])
  end

  # -------------------------------------------------------
  # Tuple key-paths
  # -------------------------------------------------------

  test "locked path written as a tuple behaves like the list form" do
    base = %{db: %{password: "s3cr3t", pool: 5}}
    override = %{db: %{password: "pwned", pool: 10}}

    assert {:error, [conflict]} =
             StrictConfigMerger.merge(base, override, locked: [{:db, :password}])

    assert conflict.type == :locked_violation
    assert conflict.path == [:db, :password]
    assert conflict.base == "s3cr3t"
    assert conflict.override == "pwned"
  end

  test "tuple locked path untouched by the override is not a conflict" do
    base = %{db: %{password: "s3cr3t", pool: 5}}
    override = %{db: %{pool: 10}}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, locked: [{:db, :password}])
    assert merged.db == %{password: "s3cr3t", pool: 10}
  end

  test "required path written as a tuple behaves like the list form" do
    base = %{a: %{b: 1}}
    override = %{}

    assert {:error, [conflict]} =
             StrictConfigMerger.merge(base, override, required: [{:a, :missing}])

    assert conflict.type == :missing_required
    assert conflict.path == [:a, :missing]

    assert {:ok, _merged} = StrictConfigMerger.merge(base, override, required: [{:a, :b}])
  end

  # -------------------------------------------------------
  # List strategy
  # -------------------------------------------------------

  test "append list strategy concatenates and returns :ok" do
    base = %{plugins: ["core"]}
    override = %{plugins: ["extra"]}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, list_strategy: :append)
    assert merged.plugins == ["core", "extra"]
  end

  # -------------------------------------------------------
  # Multiple conflicts sorted by path
  # -------------------------------------------------------

  test "multiple conflicts are returned sorted by path" do
    base = %{a: 1, z: 2}
    override = %{a: "x", z: [1]}

    assert {:error, conflicts} = StrictConfigMerger.merge(base, override, strict: true)
    assert Enum.map(conflicts, & &1.path) == [[:a], [:z]]
    assert Enum.all?(conflicts, &(&1.type == :type_mismatch))
  end

  test "conflicts across mismatch, lock, and required are all reported" do
    base = %{port: 1, secret: "keep"}
    override = %{port: "two", secret: "change"}

    assert {:error, conflicts} =
             StrictConfigMerger.merge(base, override,
               strict: true,
               locked: [[:secret]],
               required: [[:missing]]
             )

    types = conflicts |> Enum.map(& &1.type) |> Enum.sort()
    assert types == [:locked_violation, :missing_required, :type_mismatch]
  end

  test "tuple and list key-paths mix freely across locked and required" do
    base = %{db: %{password: "s3cr3t"}, port: 4000}
    override = %{db: %{password: "pwned"}, port: 9000}

    assert {:error, conflicts} =
             StrictConfigMerger.merge(base, override,
               locked: [{:db, :password}],
               required: [[:tls, :cert]]
             )

    assert Enum.map(conflicts, & &1.path) == [[:db, :password], [:tls, :cert]]
    types = conflicts |> Enum.map(& &1.type) |> Enum.sort()
    assert types == [:locked_violation, :missing_required]
  end
end
