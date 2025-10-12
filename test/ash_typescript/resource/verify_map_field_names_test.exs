# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.VerifyMapFieldNamesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 integration - invalid field names" do
    test "detects invalid field names in map type constraints" do
      # With new Spark behavior, errors are emitted as warnings during compilation
      # So we define the module normally (it compiles with warnings)
      defmodule TestResourceWithInvalidMapFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidMapFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :metadata, :map do
            public? true

            constraints fields: [
                          field_1: [type: :string],
                          is_active?: [type: :boolean]
                        ]
          end
        end
      end

      # Our VerifierChecker should catch these warnings and treat them as errors
      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestResourceWithInvalidMapFields])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end

    test "detects invalid field names in keyword type constraints" do
      defmodule TestResourceWithInvalidKeywordFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidKeywordFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :config, :keyword do
            public? true

            constraints fields: [
                          setting_1: [type: :string],
                          enabled?: [type: :boolean]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestResourceWithInvalidKeywordFields])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end

    test "detects invalid field names in tuple type constraints" do
      defmodule TestResourceWithInvalidTupleFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidTupleFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :coordinates, :tuple do
            public? true

            constraints fields: [
                          value_1: [type: :integer],
                          value_2: [type: :integer]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestResourceWithInvalidTupleFields])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end

    test "detects invalid field names in union type members" do
      defmodule TestResourceWithInvalidUnionMapFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidUnionMapFields"
        end

        attributes do
          uuid_primary_key :id

          attribute :data, :union do
            public? true

            constraints types: [
                          simple: [
                            type: :map,
                            constraints: [
                              fields: [
                                field_1: [type: :string],
                                is_valid?: [type: :boolean]
                              ]
                            ]
                          ]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestResourceWithInvalidUnionMapFields])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end

    test "detects invalid field names in calculation return types" do
      defmodule TestResourceWithInvalidCalcMapFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidCalcMapFields"
        end

        attributes do
          uuid_primary_key :id
        end

        calculations do
          calculate :computed_data, :map do
            public? true

            constraints fields: [
                          result_1: [type: :string],
                          is_valid?: [type: :boolean]
                        ]

            calculation fn records, _context ->
              Enum.map(records, fn _record ->
                %{result_1: "test", is_valid?: true}
              end)
            end
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestResourceWithInvalidCalcMapFields])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in map\/keyword\/tuple/
    end
  end
end
