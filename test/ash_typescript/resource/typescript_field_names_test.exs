# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.TypescriptFieldNamesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 integration - typescript_field_names" do
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
