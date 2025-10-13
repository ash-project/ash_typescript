# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.VerifyNestedMapFieldNamesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 integration - nested invalid field names" do
    test "detects invalid field names in nested map within map" do
      defmodule TestResourceWithNestedMapInvalidFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithNestedMapInvalidFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :outer, :map do
            public? true

            constraints fields: [
                          valid_field: [type: :string],
                          nested_map: [
                            type: :map,
                            constraints: [
                              fields: [
                                inner_field_1: [type: :string],
                                is_nested?: [type: :boolean]
                              ]
                            ]
                          ]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestResourceWithNestedMapInvalidFields
        ])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end

    test "detects invalid field names in nested keyword within map" do
      defmodule TestResourceWithNestedKeywordInvalidFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithNestedKeywordInvalidFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :data, :map do
            public? true

            constraints fields: [
                          config: [
                            type: :keyword,
                            constraints: [
                              fields: [
                                option_1: [type: :string],
                                enabled?: [type: :boolean]
                              ]
                            ]
                          ]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestResourceWithNestedKeywordInvalidFields
        ])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end

    test "detects invalid field names in union member within map" do
      defmodule TestResourceWithUnionInMapInvalidFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithUnionInMapInvalidFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :data, :map do
            public? true

            constraints fields: [
                          content: [
                            type: :union,
                            constraints: [
                              types: [
                                text: [
                                  type: :map,
                                  constraints: [
                                    fields: [
                                      text_field_1: [type: :string],
                                      is_bold?: [type: :boolean]
                                    ]
                                  ]
                                ],
                                image: [
                                  type: :map,
                                  constraints: [
                                    fields: [
                                      url: [type: :string],
                                      alt_text_2: [type: :string]
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

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestResourceWithUnionInMapInvalidFields
        ])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end

    test "detects invalid field names in deeply nested structures" do
      defmodule TestResourceWithDeeplyNestedInvalidFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithDeeplyNestedInvalidFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :level1, :map do
            public? true

            constraints fields: [
                          level2: [
                            type: :map,
                            constraints: [
                              fields: [
                                level3: [
                                  type: :map,
                                  constraints: [
                                    fields: [
                                      deep_field_1: [type: :string],
                                      is_deep?: [type: :boolean]
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

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestResourceWithDeeplyNestedInvalidFields
        ])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end
  end
end
