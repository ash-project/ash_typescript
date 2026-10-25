# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes.FieldsForTest do
  # `AshTypescript.CustomTypes.fields_for/3`: the field specs a custom type
  # declares for ash_rpc's decoration, in precedence order (manifest entry >
  # type callbacks > built-in > `composite_types/1`), and the hint text for an
  # undeclared map-like type.
  use ExUnit.Case, async: false

  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.{Builtin, Field, MapType, Scalar}
  alias AshTypescript.CustomTypes.FieldsForTest, as: T

  defmodule MapStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  defmodule WithCallbacks do
    @moduledoc false
    use MapStorage

    def typescript_fields,
      do: [
        primary: [type: :string, allow_nil?: false],
        accent_color: [type: :string, constraints: [max_length: 7]]
      ]

    def typescript_field_names, do: [accent_color: "accentColour"]
  end

  defmodule CallbacksOnly do
    @moduledoc false
    use MapStorage

    def typescript_fields, do: [label: [type: :string]]
  end

  defmodule NamesOnly do
    @moduledoc false
    use MapStorage

    def typescript_field_names, do: [first: "firstOne"]
  end

  defmodule Composite do
    @moduledoc false
    use Ash.Type

    @impl true
    def constraints, do: [unit: [type: :atom, default: :cm]]
    @impl true
    def storage_type(_), do: :map
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
    @impl true
    def composite?(_), do: true
    @impl true
    def composite_types(constraints),
      do: [
        {:length, :integer, [min: if(constraints[:unit] == :cm, do: 0, else: 1)]},
        {:unit_name, :unit_key, :string, []}
      ]

    def typescript_field_names, do: [unit_name: "unitName"]
  end

  defmodule Scalarish do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :string
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  defmodule TypeNamed do
    @moduledoc false
    use MapStorage

    def typescript_type_name, do: "Custom.TypeNamed"
  end

  defmodule NewOverCallbacks do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.CustomTypes.FieldsForTest.WithCallbacks
  end

  defmodule NewWithOwn do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.CustomTypes.FieldsForTest.WithCallbacks

    def typescript_fields, do: [own: [type: :integer]]
  end

  defmodule NewWithNames do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.CustomTypes.FieldsForTest.WithCallbacks

    def typescript_field_names, do: [accent_color: "accentTone"]
  end

  defmodule NewOverMoney do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshMoney.Types.Money
  end

  defmodule NewOverComposite do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.CustomTypes.FieldsForTest.Composite
  end

  defmodule ScalarFields do
    @moduledoc false
    use MapStorage

    def typescript_fields,
      do: [
        code: [
          type: AshTypescript.CustomTypes.FieldsForTest.Scalarish,
          constraints: [max_length: 8]
        ],
        codes: [type: {:array, AshTypescript.CustomTypes.FieldsForTest.Scalarish}],
        label: [type: :string]
      ]
  end

  defmodule NewOverScalarFields do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.CustomTypes.FieldsForTest.ScalarFields
  end

  defmodule CompositeScalar do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :map
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
    @impl true
    def composite?(_), do: true
    @impl true
    def composite_types(_),
      do: [{:code, AshTypescript.CustomTypes.FieldsForTest.Scalarish, [max_length: 3]}]
  end

  defmodule NotAList do
    @moduledoc false
    use MapStorage

    def typescript_fields, do: :not_a_list
  end

  defp builtin, do: Map.new(Builtin.entries(), &{&1.module, &1})

  defp map_entry(module, fields), do: %MapType{module: module, fields: fields}

  describe "precedence" do
    test "a manifest map entry wins over the type's callbacks, and only its client names apply" do
      declared = %{
        T.WithCallbacks =>
          map_entry(T.WithCallbacks, [
            %Field{name: :hue, type: Ash.Type.String, allow_nil?: false, client_name: "HUE"},
            %Field{name: :accent_color, type: Ash.Type.String, description: "Accent"}
          ])
      }

      assert CustomTypes.fields_for(T.WithCallbacks, declared, builtin()) == [
               hue: [
                 type: Ash.Type.String,
                 constraints: [],
                 allow_nil?: false,
                 client_name: "HUE"
               ],
               accent_color: [
                 type: Ash.Type.String,
                 constraints: [],
                 allow_nil?: true,
                 description: "Accent"
               ]
             ]
    end

    test "typescript_fields/0 wins over a built-in, named by typescript_field_names/0" do
      builtin =
        Map.put(
          builtin(),
          T.WithCallbacks,
          map_entry(T.WithCallbacks, [%Field{name: :ignored, type: Ash.Type.String}])
        )

      assert CustomTypes.fields_for(T.WithCallbacks, %{}, builtin) == [
               primary: [type: :string, allow_nil?: false],
               accent_color: [
                 type: :string,
                 constraints: [max_length: 7],
                 client_name: "accentColour"
               ]
             ]
    end

    test "a built-in map entry applies when nothing else does (the Money stub)" do
      assert CustomTypes.fields_for(AshMoney.Types.Money, %{}, builtin()) == [
               currency: [type: Ash.Type.String, constraints: [], allow_nil?: false],
               amount: [type: Ash.Type.Decimal, constraints: [], allow_nil?: false]
             ]
    end

    test "a built-in field's client_name applies only where typescript_field_names/0 has none" do
      builtin =
        Map.put(
          builtin(),
          T.NamesOnly,
          map_entry(T.NamesOnly, [
            %Field{name: :first, type: Ash.Type.String, client_name: "builtinFirst"},
            %Field{name: :second, type: Ash.Type.String, client_name: "builtinSecond"}
          ])
        )

      assert CustomTypes.fields_for(T.NamesOnly, %{}, builtin) == [
               first: [
                 type: Ash.Type.String,
                 constraints: [],
                 allow_nil?: true,
                 client_name: "firstOne"
               ],
               second: [
                 type: Ash.Type.String,
                 constraints: [],
                 allow_nil?: true,
                 client_name: "builtinSecond"
               ]
             ]
    end

    test "composite_types/1 at the default constraints gives non-null fields" do
      assert CustomTypes.fields_for(T.Composite, %{}, builtin()) == [
               length: [type: :integer, constraints: [min: 0], allow_nil?: false],
               unit_name: [
                 type: :string,
                 constraints: [],
                 allow_nil?: false,
                 client_name: "unitName"
               ]
             ]
    end

    test "a manifest scalar entry declares no fields, whatever the type's callbacks say" do
      declared = %{T.WithCallbacks => %Scalar{module: T.WithCallbacks, type: Ash.Type.String}}
      assert CustomTypes.fields_for(T.WithCallbacks, declared, builtin()) == nil
    end

    test "a type with nothing declared has no fields" do
      assert CustomTypes.fields_for(T.Scalarish, %{}, builtin()) == nil
      assert CustomTypes.fields_for(T.TypeNamed, %{}, builtin()) == nil
      assert CustomTypes.fields_for(AshDoubleEntry.ULID, %{}, builtin()) == nil
      assert CustomTypes.fields_for(String, %{}, builtin()) == nil
      assert CustomTypes.fields_for(T.NotAModule, %{}, builtin()) == nil
    end
  end

  describe "NewTypes" do
    test "a NewType inherits its subtype's typescript_fields/0 and names" do
      assert CustomTypes.fields_for(T.NewOverCallbacks, %{}, builtin()) ==
               CustomTypes.fields_for(T.WithCallbacks, %{}, builtin())
    end

    test "a NewType's own typescript_field_names/0 win over its subtype's" do
      assert CustomTypes.fields_for(T.NewWithNames, %{}, builtin()) == [
               primary: [type: :string, allow_nil?: false],
               accent_color: [
                 type: :string,
                 constraints: [max_length: 7],
                 client_name: "accentTone"
               ]
             ]
    end

    test "a NewType's own typescript_fields/0 wins" do
      assert CustomTypes.fields_for(T.NewWithOwn, %{}, builtin()) == [own: [type: :integer]]
    end

    test "a NewType's own manifest entry wins over its subtype's callbacks" do
      declared = %{
        T.NewOverCallbacks =>
          map_entry(T.NewOverCallbacks, [%Field{name: :x, type: Ash.Type.Integer}])
      }

      assert CustomTypes.fields_for(T.NewOverCallbacks, declared, builtin()) == [
               x: [type: Ash.Type.Integer, constraints: [], allow_nil?: true]
             ]
    end

    test "a NewType inherits its subtype's manifest entry" do
      declared = %{
        T.WithCallbacks => map_entry(T.WithCallbacks, [%Field{name: :x, type: Ash.Type.Integer}])
      }

      assert CustomTypes.fields_for(T.NewOverCallbacks, declared, builtin()) == [
               x: [type: Ash.Type.Integer, constraints: [], allow_nil?: true]
             ]
    end

    test "a NewType over the Money stub inherits the built-in" do
      assert CustomTypes.fields_for(T.NewOverMoney, %{}, builtin()) ==
               CustomTypes.fields_for(AshMoney.Types.Money, %{}, builtin())
    end

    test "a NewType over a composite type gets its composite_types/1 fields" do
      assert CustomTypes.fields_for(T.NewOverComposite, %{}, builtin()) ==
               CustomTypes.fields_for(T.Composite, %{}, builtin())
    end
  end

  describe "fields typed by a scalar entry" do
    # The scalar's constraints go under the field's (the field winning per
    # key, under `items:` for an array), whichever source supplies the fields.
    setup do
      regex = {Spark.Regex, :cache, ["^code-", []]}

      scalar = %Scalar{
        module: T.Scalarish,
        type: Ash.Type.String,
        constraints: [match: regex, max_length: 20]
      }

      %{scalar: scalar, regex: regex}
    end

    test "typescript_fields/0, and a NewType inheriting them", %{scalar: scalar, regex: regex} do
      declared = %{T.Scalarish => scalar}

      expected = [
        code: [type: T.Scalarish, constraints: [match: regex, max_length: 8]],
        codes: [
          type: {:array, T.Scalarish},
          constraints: [items: [match: regex, max_length: 20]]
        ],
        label: [type: :string]
      ]

      assert CustomTypes.fields_for(T.ScalarFields, declared, builtin()) == expected
      assert CustomTypes.fields_for(T.NewOverScalarFields, declared, builtin()) == expected
    end

    test "composite_types/1, with a built-in scalar entry", %{scalar: scalar, regex: regex} do
      builtin = Map.put(builtin(), T.Scalarish, scalar)

      assert CustomTypes.fields_for(T.CompositeScalar, %{}, builtin) == [
               code: [
                 type: T.Scalarish,
                 constraints: [match: regex, max_length: 3],
                 allow_nil?: false
               ]
             ]
    end

    test "a built-in map entry's fields", %{scalar: scalar, regex: regex} do
      builtin =
        builtin()
        |> Map.put(T.Scalarish, scalar)
        |> Map.put(T.NamesOnly, map_entry(T.NamesOnly, [%Field{name: :x, type: T.Scalarish}]))

      assert CustomTypes.fields_for(T.NamesOnly, %{}, builtin) == [
               x: [
                 type: T.Scalarish,
                 constraints: [match: regex, max_length: 20],
                 allow_nil?: true
               ]
             ]
    end

    test "fields without a scalar entry are left as declared" do
      assert CustomTypes.fields_for(T.ScalarFields, %{}, builtin()) ==
               T.ScalarFields.typescript_fields()
    end
  end

  describe "a malformed typescript_fields/0 result" do
    test "is passed through for ash_rpc to report" do
      assert CustomTypes.fields_for(T.NotAList, %{}, builtin()) == :not_a_list
    end
  end

  describe "compile_dependencies/3" do
    defp custom_type(module),
      do: %Ash.Info.Manifest.Type{
        kind: :map,
        module: module,
        custom: %{ash_rpc: %{custom_type: true}}
      }

    test "lists the modules whose callbacks supplied a definition's fields" do
      declared = %{
        T.NamesOnly => map_entry(T.NamesOnly, [%Field{name: :x, type: Ash.Type.Integer}])
      }

      manifest = %Ash.Info.Manifest{
        types: [
          custom_type(T.WithCallbacks),
          custom_type(T.Composite),
          custom_type(T.NewOverCallbacks),
          custom_type(T.NewWithOwn),
          custom_type(T.NewOverComposite),
          custom_type(T.NewOverMoney),
          custom_type(AshMoney.Types.Money),
          custom_type(T.NamesOnly),
          %Ash.Info.Manifest.Type{kind: :map, module: T.CallbacksOnly}
        ]
      }

      assert manifest |> CustomTypes.compile_dependencies(declared, builtin()) |> Enum.sort() ==
               Enum.sort([T.WithCallbacks, T.Composite, T.NewWithOwn, T.NewOverComposite])
    end

    test "the test manifest depends on ColorPalette" do
      %{declared: declared, builtin: builtin} =
        Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :custom_types)

      assert AshTypescript.Test.Todo.ColorPalette in CustomTypes.compile_dependencies(
               AshTypescript.manifest(),
               declared,
               builtin
             )
    end
  end

  describe "a DSL field" do
    defp compile_manifest!(name, body) do
      module = Module.concat(T, name)

      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Module.create(
          module,
          quote do
            use AshTypescript.Manifest,
              otp_app: :ash_typescript,
              domains: [AshTypescript.Test.SecondDomain]

            unquote(body)
          end,
          Macro.Env.location(__ENV__)
        )
      end)

      module
    end

    test "without allow_nil? is nullable" do
      module =
        compile_manifest!(
          AllowNilManifest,
          quote do
            custom_types do
              map SomeLib.Shape do
                field :sides, :integer
                field :name, :string, allow_nil?: false
              end
            end
          end
        )

      %{declared: declared, builtin: builtin} =
        Spark.Dsl.Extension.get_persisted(module, :custom_types)

      assert CustomTypes.fields_for(SomeLib.Shape, declared, builtin) == [
               sides: [type: Ash.Type.Integer, constraints: [], allow_nil?: true],
               name: [type: Ash.Type.String, constraints: [], allow_nil?: false]
             ]
    end
  end

  describe "hint/3" do
    @base "Declare its fields with a `map` entry in your manifest module's `custom_types` " <>
            "section, a `typescript_fields/0` callback on the type, or " <>
            "`composite?/1` + `composite_types/1`."

    test "names the ways to declare fields" do
      assert CustomTypes.hint(T.Scalarish, %{}, builtin()) == @base
    end

    test "says to remove typescript_type_name/0 when the type exports it" do
      assert CustomTypes.hint(T.TypeNamed, %{}, builtin()) ==
               @base <>
                 " Remove `typescript_type_name/0`: a map-like type's TypeScript is " <>
                 "generated from its fields."
    end

    test "says to remove the scalar declaration when one covers the type" do
      declared = %{T.Scalarish => %Scalar{module: T.Scalarish, type: Ash.Type.String}}

      assert CustomTypes.hint(T.Scalarish, declared, builtin()) ==
               @base <>
                 " Remove the `scalar` declaration: a map-like type's TypeScript is " <>
                 "generated from its fields."

      assert CustomTypes.hint(AshDoubleEntry.ULID, %{}, builtin()) =~
               "Remove the `scalar` declaration"
    end

    test "names both when both apply" do
      declared = %{T.TypeNamed => %Scalar{module: T.TypeNamed, type: Ash.Type.String}}

      assert CustomTypes.hint(T.TypeNamed, declared, builtin()) ==
               @base <>
                 " Remove `typescript_type_name/0` and the `scalar` declaration: a map-like " <>
                 "type's TypeScript is generated from its fields."
    end
  end

  describe "hint_fun/1" do
    test "closes over persisted declarations and built-ins" do
      declared = %{T.Scalarish => %Scalar{module: T.Scalarish, type: Ash.Type.String}}
      hint = CustomTypes.hint_fun(%{declared: declared, builtin: %{}})

      assert hint.(T.Scalarish) == CustomTypes.hint(T.Scalarish, declared, %{})
      assert hint.(AshDoubleEntry.ULID) == CustomTypes.hint(AshDoubleEntry.ULID, declared, %{})
      refute hint.(AshDoubleEntry.ULID) =~ "Remove the `scalar` declaration"
    end

    test "uses the built-ins alone for nil" do
      hint = CustomTypes.hint_fun(nil)

      assert hint.(AshDoubleEntry.ULID) == CustomTypes.hint(AshDoubleEntry.ULID, %{}, builtin())
      assert hint.(AshDoubleEntry.ULID) =~ "Remove the `scalar` declaration"
    end
  end

  describe "AshTypescript.RpcMappingSource" do
    test "custom_type_fields/1 uses the built-ins and the type's callbacks, no manifest entries" do
      for module <- [
            AshMoney.Types.Money,
            T.WithCallbacks,
            T.Composite,
            T.NewOverMoney,
            T.Scalarish
          ] do
        assert AshTypescript.RpcMappingSource.custom_type_fields(module) ==
                 CustomTypes.fields_for(module, %{}, builtin())
      end
    end

    test "custom_type_fields_hint/1 is the hint without manifest entries" do
      for module <- [T.Scalarish, T.TypeNamed, AshDoubleEntry.ULID] do
        assert AshTypescript.RpcMappingSource.custom_type_fields_hint(module) ==
                 CustomTypes.hint(module, %{}, builtin())
      end
    end
  end
end
