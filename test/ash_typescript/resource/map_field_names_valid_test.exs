defmodule AshTypescript.Resource.MapFieldNamesValidTest do
  use ExUnit.Case, async: true

  describe "valid field names" do
    test "allows valid field names in map type constraints" do
      defmodule TestResourceWithValidMapFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithValidMapFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :metadata, :map do
            public? true

            constraints fields: [
                          field1: [type: :string],
                          is_active: [type: :boolean],
                          normal_field: [type: :string]
                        ]
          end
        end
      end

      # Should compile without errors
      assert TestResourceWithValidMapFields
    end

    test "allows valid field names in nested structures" do
      defmodule TestResourceWithValidNestedFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithValidNestedFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :data, :map do
            public? true

            constraints fields: [
                          nested: [
                            type: :map,
                            constraints: [
                              fields: [
                                field1: [type: :string],
                                isActive: [type: :boolean],
                                deep_nested: [
                                  type: :map,
                                  constraints: [
                                    fields: [
                                      value: [type: :string]
                                    ]
                                  ]
                                ]
                              ]
                            ]
                          ]
                        ]
          end
        end
      end

      # Should compile without errors
      assert TestResourceWithValidNestedFields
    end
  end
end
