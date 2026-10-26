# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Dsl do
  @moduledoc false

  @mapping_type {:or, [:string, :mfa]}

  @mapping_doc "A string, or an MFA `{m, f, a}` called as `apply(m, f, [constraints | a])` with the use's constraints, returning a string."

  @field %Spark.Dsl.Entity{
    name: :field,
    target: AshTypescript.CustomTypes.Field,
    describe: """
    A field of a `map` custom type. `type` may be an Ash type, a module with
    a `scalar` or `map` entry, or a built-in. When it is a declared scalar,
    the field's `constraints` are merged over the scalar's, the field winning
    per key.
    """,
    examples: [
      "field :primary, SomeLib.HexColor, allow_nil?: false",
      ~s(field :accent_color, :string, client_name: "accentColour")
    ],
    args: [:name, :type],
    transform: {AshTypescript.CustomTypes.Field, :transform, []},
    schema: [
      name: [type: :atom, required: true, doc: "The field's name in the value."],
      type: [
        type: :any,
        required: true,
        doc: "The field's Ash type (`:string`, `{:array, :integer}`, a type module)."
      ],
      constraints: [
        type: :keyword_list,
        default: [],
        doc: "Constraints for `type`. Regexes are stored as `Spark.Regex` MFAs."
      ],
      allow_nil?: [
        type: :boolean,
        default: true,
        doc: "Whether the field may be `nil`. Set to `false` to make it non-null."
      ],
      client_name: [
        type: :string,
        doc: "The field's client name, in place of the output formatter's."
      ],
      description: [type: :string, doc: "A description of the field."]
    ]
  }

  @scalar %Spark.Dsl.Entity{
    name: :scalar,
    target: AshTypescript.CustomTypes.Scalar,
    describe: """
    Declares a custom type you don't own whose values are a single value of
    a base Ash type. Its TypeScript, zod and valibot are generated from the
    base type and constraints unless `typescript`, `zod` or `valibot` is
    given.
    """,
    examples: [
      """
      scalar SomeLib.HexColor, :string do
        constraints match: ~r/^#[0-9a-fA-F]{6}$/
        typescript "`#${string}`"
      end
      """,
      "scalar SomeLib.Percentage, :integer, constraints: [min: 0, max: 100]"
    ],
    args: [:module, :type],
    transform: {AshTypescript.CustomTypes.Scalar, :transform, []},
    schema: [
      module: [type: :atom, required: true, doc: "The custom type module."],
      type: [
        type: :any,
        required: true,
        doc: "The base Ash type (`:string`, `{:array, :string}`, a type module)."
      ],
      constraints: [
        type: :keyword_list,
        default: [],
        doc: "Constraints for the base type. Regexes are stored as `Spark.Regex` MFAs."
      ],
      typescript: [type: @mapping_type, doc: "The TypeScript type. #{@mapping_doc}"],
      zod: [type: @mapping_type, doc: "The zod schema. #{@mapping_doc}"],
      valibot: [type: @mapping_type, doc: "The valibot schema. #{@mapping_doc}"]
    ]
  }

  @map %Spark.Dsl.Entity{
    name: :map,
    target: AshTypescript.CustomTypes.MapType,
    describe: """
    Declares the fields of a map-like custom type you don't own (one with
    `storage_type :map`, or composite). Its TypeScript is generated from its
    fields, so a map has no `typescript` option: a map-like type that only
    names a TypeScript type declares its fields instead (see "Migrating
    from `typescript_type_name/0`" in the Custom Types guide). A map needs
    at least one field.
    """,
    examples: [
      """
      map SomeLib.ColorPalette do
        type_name "Palette"
        field :primary, SomeLib.HexColor, allow_nil?: false
        field :accent_color, SomeLib.HexColor, client_name: "accentColour"
        zod "MyZod.colorPalette"
      end
      """
    ],
    args: [:module],
    entities: [fields: [@field]],
    schema: [
      module: [type: :atom, required: true, doc: "The custom type module."],
      zod: [
        type: @mapping_type,
        doc: "A zod schema in place of the generated one. #{@mapping_doc}"
      ],
      valibot: [
        type: @mapping_type,
        doc: "A valibot schema in place of the generated one. #{@mapping_doc}"
      ],
      type_name: [
        type: :string,
        doc:
          "The name of the generated TypeScript alias (default: the module name joined, " <>
            "`SomeLib.Coordinates` → `SomeLibCoordinates`). The named zod and valibot " <>
            "schemas are this name followed by `zod_schema_suffix` / `valibot_schema_suffix`."
      ]
    ]
  }

  @custom_types %Spark.Dsl.Section{
    name: :custom_types,
    describe: """
    Declares custom types (`use Ash.Type` modules) you don't own: a `scalar`
    for a single-value type, a `map` for a map-like one. Each module appears
    once. A declaration replaces the type's own callbacks
    (`typescript_type_name/0`, `typescript_fields/0`) and its built-in entry,
    if any. Built-in entries cover `AshMoney.Types.Money`,
    `AshDoubleEntry.ULID` and `AshPostgres.Ltree`.
    """,
    examples: [
      """
      custom_types do
        scalar SomeLib.HexColor, :string, constraints: [match: ~r/^#[0-9a-f]{6}$/]

        map SomeLib.ColorPalette do
          field :primary, SomeLib.HexColor, allow_nil?: false
        end
      end
      """
    ],
    entities: [@scalar, @map]
  }

  use Spark.Dsl.Extension,
    sections: [@custom_types],
    transformers: [
      AshTypescript.Manifest.Transformers.NormalizeCustomTypes,
      AshTypescript.Manifest.Transformers.BuildManifest,
      AshTypescript.Manifest.Transformers.DecorateManifest
    ],
    verifiers: [
      AshTypescript.Manifest.Verifiers.VerifyRpc,
      AshTypescript.Manifest.Verifiers.VerifyActionTypes,
      AshTypescript.Manifest.Verifiers.VerifyMappableTypes,
      AshTypescript.Manifest.Verifiers.VerifyCustomTypeNames,
      AshTypescript.Manifest.Verifiers.VerifyUniqueInputFieldNames,
      AshTypescript.Manifest.Verifiers.VerifyMetadataFieldNames,
      AshTypescript.Manifest.Verifiers.VerifyTypedQueryFields,
      AshTypescript.Manifest.Verifiers.VerifyIdentities,
      AshTypescript.Manifest.Verifiers.VerifyRpcWarnings
    ]
end
