# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.VerifyFieldNamesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  alias AshTypescript.Resource.Verifiers.VerifyFieldNames

  describe "invalid_name?/1" do
    test "detects question marks in names" do
      assert VerifyFieldNames.invalid_name?(:has_review?)
      assert VerifyFieldNames.invalid_name?(:is_active?)
      assert VerifyFieldNames.invalid_name?("has_review?")
    end

    test "detects underscores followed by numbers" do
      assert VerifyFieldNames.invalid_name?(:field_1)
      assert VerifyFieldNames.invalid_name?(:address_line_1)
      assert VerifyFieldNames.invalid_name?("item_2")
    end

    test "allows valid names" do
      refute VerifyFieldNames.invalid_name?(:has_review)
      refute VerifyFieldNames.invalid_name?(:is_active)
      refute VerifyFieldNames.invalid_name?(:field1)
      refute VerifyFieldNames.invalid_name?(:addressLine1)
    end
  end

  describe "verify/1 - calculations with question marks" do
    test "rejects calculation with question mark when no field_names mapping exists" do
      defmodule ResourceWithUnmappedQuestionMarkCalc do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithUnmappedQuestionMarkCalc"
        end

        attributes do
          uuid_primary_key :id
        end

        calculations do
          calculate :has_review?, :boolean, expr(true) do
            public? true
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithUnmappedQuestionMarkCalc])

      assert {:error, error_message} = result
      assert error_message =~ "Invalid field names"
      assert error_message =~ "has_review?"
      assert error_message =~ "calculation"
      assert error_message =~ "has_review"
    end

    test "accepts calculation with question mark when field_names mapping exists" do
      defmodule ResourceWithMappedQuestionMarkCalc do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithMappedQuestionMarkCalc"
          field_names has_review?: "hasReview"
        end

        attributes do
          uuid_primary_key :id
        end

        calculations do
          calculate :has_review?, :boolean, expr(true) do
            public? true
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithMappedQuestionMarkCalc])

      assert :ok = result
    end
  end

  describe "verify/1 - attributes with underscore numbers" do
    test "rejects attribute with underscore number when no field_names mapping exists" do
      defmodule ResourceWithUnmappedUnderscoreAttr do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithUnmappedUnderscoreAttr"
        end

        attributes do
          uuid_primary_key :id

          attribute :address_line_1, :string do
            public? true
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithUnmappedUnderscoreAttr])

      assert {:error, error_message} = result
      assert error_message =~ "Invalid field names"
      assert error_message =~ "address_line_1"
      assert error_message =~ "attribute"
    end

    test "accepts attribute with underscore number when field_names mapping exists" do
      defmodule ResourceWithMappedUnderscoreAttr do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithMappedUnderscoreAttr"
          field_names address_line_1: "addressLine1"
        end

        attributes do
          uuid_primary_key :id

          attribute :address_line_1, :string do
            public? true
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithMappedUnderscoreAttr])

      assert :ok = result
    end
  end

  describe "verify/1 - aggregates with question marks" do
    test "rejects aggregate with question mark when no field_names mapping exists" do
      defmodule RelatedResource do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets

        attributes do
          uuid_primary_key :id
          attribute :parent_id, :uuid
        end

        relationships do
          belongs_to :parent,
                     AshTypescript.Resource.VerifyFieldNamesTest.ResourceWithUnmappedQuestionMarkAgg do
            attribute_writable? true
            source_attribute :parent_id
          end
        end
      end

      defmodule ResourceWithUnmappedQuestionMarkAgg do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithUnmappedQuestionMarkAgg"
        end

        attributes do
          uuid_primary_key :id
        end

        relationships do
          has_many :items, AshTypescript.Resource.VerifyFieldNamesTest.RelatedResource do
            destination_attribute :parent_id
          end
        end

        aggregates do
          exists :has_items?, :items do
            public? true
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithUnmappedQuestionMarkAgg])

      assert {:error, error_message} = result
      assert error_message =~ "Invalid field names"
      assert error_message =~ "has_items?"
      assert error_message =~ "aggregate"
    end
  end

  describe "verify/1 - union member names (via VerifyMapFieldNames)" do
    test "rejects union member with question mark" do
      defmodule ResourceWithInvalidUnionMember do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithInvalidUnionMember"
        end

        attributes do
          uuid_primary_key :id

          attribute :content, Ash.Type.Union do
            public? true

            constraints types: [
                          text: [type: :string],
                          has_html?: [type: :string]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithInvalidUnionMember])

      assert {:error, error_message} = result
      assert error_message =~ "Invalid"
      assert error_message =~ "union member"
      assert error_message =~ "has_html?"
    end

    test "rejects union member with underscore number" do
      defmodule ResourceWithUnderscoreUnionMember do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithUnderscoreUnionMember"
        end

        attributes do
          uuid_primary_key :id

          attribute :content, Ash.Type.Union do
            public? true

            constraints types: [
                          text: [type: :string],
                          html_1: [type: :string]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithUnderscoreUnionMember])

      assert {:error, error_message} = result
      assert error_message =~ "Invalid"
      assert error_message =~ "union member"
      assert error_message =~ "html_1"
    end

    test "accepts valid union member names" do
      defmodule ResourceWithValidUnionMembers do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithValidUnionMembers"
        end

        attributes do
          uuid_primary_key :id

          attribute :content, Ash.Type.Union do
            public? true

            constraints types: [
                          text: [type: :string],
                          html: [type: :string],
                          markdown: [type: :string]
                        ]
          end
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([ResourceWithValidUnionMembers])

      assert :ok = result
    end
  end
end
