defmodule AshTypescript.Resource.TypescriptFieldNamesTest do
  use ExUnit.Case, async: true

  describe "NewType with typescript_field_names callback" do
    test "generates TypeScript types with mapped field names" do
      # Generate TypeScript code
      resource = AshTypescript.Test.MapFieldResource
      type_code = AshTypescript.Codegen.generate_all_schemas_for_resource(resource, [resource])

      # Check that mapped field names are used in the generated TypeScript
      assert type_code =~ "field1: string"
      assert type_code =~ "isActive: boolean"
      assert type_code =~ "line2: string | null"

      # Make sure the original names are NOT in the generated code
      refute type_code =~ "field_1:"
      refute type_code =~ "is_active?:"
      refute type_code =~ "line_2:"
    end

    test "generates Zod schemas with mapped field names" do
      # Generate Zod schemas for embedded resources
      resource = AshTypescript.Test.MapFieldResource

      zod_code =
        AshTypescript.Rpc.ZodSchemaGenerator.generate_zod_schema_for_embedded_resource(resource)

      # Check that mapped field names are used in the generated Zod schemas
      assert zod_code =~ "field1: z.string()"
      assert zod_code =~ "isActive: z.boolean()"
      assert zod_code =~ "line2: z.string().optional()"

      # Make sure the original names are NOT in the generated code
      refute zod_code =~ "field_1:"
      refute zod_code =~ "is_active?:"
      refute zod_code =~ "line_2:"
    end

    test "VerifyMapFieldNames suggests NewType with typescript_field_names for invalid names" do
      defmodule TestResourceWithInvalidMapNames do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidMapNames"
        end

        attributes do
          uuid_primary_key :id

          attribute :data, :map do
            public? true

            constraints fields: [
                          field_1: [type: :string],
                          is_active?: [type: :boolean]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestResourceWithInvalidMapNames])

      assert {:error, error_message} = result
      assert error_message =~ "create a custom Ash.Type.NewType"
      assert error_message =~ "typescript_field_names/0"
      assert error_message =~ "defmodule MyApp.MyCustomType"
    end
  end
end
