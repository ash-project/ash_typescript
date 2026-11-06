# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ResourceSchemaFieldKindsTest do
  @moduledoc """
  Resource schema lines for field shapes the test domain doesn't have:
  aggregates over typed maps, calculations with arguments that are required
  or return a list of resources, and required typed-map attributes in the
  attributes-only schema. The resources live in an inline manifest so the
  committed `test/ts` output stays as it is.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.ResourceSchemas
  alias AshTypescript.Test.InlineManifest

  defmodule Child do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "FieldKindsChild"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id

      attribute :point, :map,
        public?: true,
        allow_nil?: false,
        constraints: [fields: [x: [type: :integer, allow_nil?: false]]]

      attribute :parent_id, :uuid, public?: true
    end

    relationships do
      belongs_to :parent, AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Parent,
        public?: true,
        define_attribute?: false
    end

    actions do
      defaults [:read]
    end
  end

  defmodule ChildrenCalculation do
    @moduledoc false
    use Ash.Resource.Calculation

    @impl true
    def calculate(records, _opts, _context), do: Enum.map(records, fn _ -> [] end)
  end

  defmodule Parent do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "FieldKindsParent"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
    end

    relationships do
      has_many :children, AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Child,
        public?: true,
        destination_attribute: :parent_id
    end

    aggregates do
      first :first_point, :children, :point, public?: true
      list :points, :children, :point, public?: true
    end

    calculations do
      calculate :label, :string, expr("x") do
        public? true
        allow_nil? false
        argument :prefix, :string
      end

      calculate :tint, AshTypescript.Test.HexColor, expr("#000000") do
        public? true
        argument :shade, :integer
      end

      calculate :picked,
                {:array, :struct},
                AshTypescript.Codegen.ResourceSchemaFieldKindsTest.ChildrenCalculation do
        public? true
        constraints items: [instance_of: AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Child]
        argument :limit, :integer
      end
    end

    actions do
      defaults [:read]
    end
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    typescript_rpc do
      resource AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Parent do
        rpc_action :list_field_kinds_parents, :read
      end

      resource AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Child do
        rpc_action :list_field_kinds_children, :read
      end
    end

    resources do
      resource AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Parent
      resource AshTypescript.Codegen.ResourceSchemaFieldKindsTest.Child
    end
  end

  setup_all do
    manifest = InlineManifest.build!(domains: [Domain])

    schemas =
      AshTypescript.with_manifest(manifest, fn ->
        ResourceSchemas.generate_all_schemas_for_resources([Parent, Child], [Parent, Child], [])
      end)

    %{schemas: schemas}
  end

  test "an aggregate over a typed map is the map's type, nullable", %{schemas: schemas} do
    assert schemas =~
             ~s(  firstPoint: {x: number, __type: "TypedMap", __primitiveFields: "x"} | null;)
  end

  test "a list aggregate over a typed map is an array of the map's type", %{schemas: schemas} do
    assert schemas =~
             ~s(  points: Array<{x: number, __type: "TypedMap", __primitiveFields: "x"}>;)
  end

  test "a required calculation with arguments returns its type without null", %{
    schemas: schemas
  } do
    assert schemas =~
             ~s(  label: { __type: "ComplexCalculation"; __returnType: string; __args: { prefix?: string | null }; };)
  end

  test "a calculation with arguments returning resources returns their schema array", %{
    schemas: schemas
  } do
    assert schemas =~
             ~s(  picked: { __type: "ComplexCalculation"; __returnType: Array<FieldKindsChildResourceSchema> | null; __args: { limit?: number | null }; };)
  end

  # A type's `typescript_type/0` is its TypeScript, not the field's: the
  # field stays a calculation with arguments.
  test "a calculation with arguments returning a typescript_type/0 type keeps its arguments", %{
    schemas: schemas
  } do
    assert schemas =~
             ~s(  tint: { __type: "ComplexCalculation"; __returnType: `#${string}` | null; __args: { shade?: number | null }; };)
  end

  test "a required typed map attribute in the attributes-only schema", %{schemas: schemas} do
    [attributes_only] =
      Regex.run(~r/export type FieldKindsChildAttributesOnlySchema = \{.*?\n\};/s, schemas)

    assert attributes_only =~
             ~s(  point: {x: number, __type: "TypedMap", __primitiveFields: "x"};)
  end
end
