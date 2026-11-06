# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.StructFieldSchemasTest do
  @moduledoc """
  A `:struct` attribute with `instance_of` a plain struct and `fields`
  constraints (not a NewType, so not a named type) validates as an object of
  its fields, alone and in an array. The resource lives in an inline manifest
  so the committed `test/ts` output stays as it is.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.{SchemaCore, ValibotSchemaGenerator, ZodSchemaGenerator}
  alias AshTypescript.Test.InlineManifest

  defmodule Point do
    @moduledoc false
    defstruct [:x]
  end

  defmodule Shape do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Codegen.StructFieldSchemasTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "StructFieldShape"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id

      attribute :origin, :struct,
        public?: true,
        constraints: [
          instance_of: AshTypescript.Codegen.StructFieldSchemasTest.Point,
          fields: [x: [type: :integer]]
        ]

      attribute :corners, {:array, :struct},
        public?: true,
        constraints: [
          items: [
            instance_of: AshTypescript.Codegen.StructFieldSchemasTest.Point,
            fields: [x: [type: :integer]]
          ]
        ]
    end

    actions do
      defaults [:read, create: [:origin, :corners]]
    end
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    typescript_rpc do
      resource AshTypescript.Codegen.StructFieldSchemasTest.Shape do
        rpc_action :create_struct_field_shape, :create
      end
    end

    resources do
      resource AshTypescript.Codegen.StructFieldSchemasTest.Shape
    end
  end

  setup_all do
    %{manifest: InlineManifest.build!(domains: [Domain])}
  end

  defp schemas(manifest, formatter) do
    AshTypescript.with_manifest(manifest, fn ->
      SchemaCore.generate_schemas_for_resources(formatter, [Shape])
    end)
  end

  test "zod", %{manifest: manifest} do
    assert schemas(manifest, ZodSchemaGenerator) =~ """
           export const StructFieldShapeZodSchema = z.object({
             corners: z.array(z.object({ x: z.number().int().nullable().optional() })).nullable().optional(),
             id: z.uuid().optional(),
             origin: z.object({ x: z.number().int().nullable().optional() }).nullable().optional(),
           });
           """
  end

  test "valibot", %{manifest: manifest} do
    assert schemas(manifest, ValibotSchemaGenerator) =~
             "  origin: v.optional(v.nullable(v.object({ x: v.optional(v.nullable(v.pipe(v.number(), v.integer()))) }))),\n"
  end
end
