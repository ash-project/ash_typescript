# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.Transformers.PersistFormattedFieldsTest do
  use ExUnit.Case, async: true

  alias AshTypescript.FieldFormatter
  alias AshTypescript.Resource.Info

  defmodule PlainResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "PlainResource"

      field_names address_line_1: "addressLine1",
                  is_active?: "isActive"
    end

    attributes do
      uuid_primary_key :id
      attribute :first_name, :string, public?: true
      attribute :address_line_1, :string, public?: true
      attribute :is_active?, :boolean, public?: true
      attribute :is_super_admin, :boolean, public?: true
    end
  end

  defmodule ResourceWithCallback do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "ResourceWithCallback"
      field_names is_active?: "isActiveFromDsl"
    end

    attributes do
      uuid_primary_key :id
      attribute :is_active?, :boolean, public?: true
      attribute :first_name, :string, public?: true
    end

    # Module-level callback — takes priority over `field_names` DSL per the
    # documented precedence in `compute_field_for_client/3`.
    def typescript_field_names do
      [is_active?: "isActiveFromCallback"]
    end
  end

  defmodule NonTypescriptResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defmodule LinkedResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :resource_with_all_kinds_id, :uuid, public?: true
    end
  end

  defmodule ResourceWithAllKinds do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "ResourceWithAllKinds"
    end

    attributes do
      uuid_primary_key :id
      attribute :first_name, :string, public?: true
    end

    relationships do
      has_many :linked_resources, LinkedResource, public?: true
    end

    calculations do
      calculate :display_name, :string, expr(first_name) do
        public? true
      end
    end

    aggregates do
      count :linked_count, :linked_resources do
        public? true
      end
    end
  end

  describe "Resource.Info.get_formatted_field/3" do
    test "returns formatted name for unmapped public attribute" do
      assert Info.get_formatted_field(PlainResource, :first_name, :camel_case) == "firstName"
      assert Info.get_formatted_field(PlainResource, :first_name, :snake_case) == "first_name"
      assert Info.get_formatted_field(PlainResource, :first_name, :pascal_case) == "FirstName"
    end

    test "returns the field_names override regardless of formatter" do
      # Override wins for ALL builtin formatters — the DSL value is the literal
      # client name with no further formatting applied.
      assert Info.get_formatted_field(PlainResource, :address_line_1, :camel_case) ==
               "addressLine1"

      assert Info.get_formatted_field(PlainResource, :address_line_1, :snake_case) ==
               "addressLine1"

      assert Info.get_formatted_field(PlainResource, :address_line_1, :pascal_case) ==
               "addressLine1"
    end

    test "applies formatter to fields without override" do
      assert Info.get_formatted_field(PlainResource, :is_super_admin, :camel_case) ==
               "isSuperAdmin"

      assert Info.get_formatted_field(PlainResource, :is_super_admin, :pascal_case) ==
               "IsSuperAdmin"
    end

    test "returns nil for missing field" do
      assert Info.get_formatted_field(PlainResource, :nonexistent_field, :camel_case) == nil
    end

    test "returns nil for non-AshTypescript resource" do
      assert Info.get_formatted_field(NonTypescriptResource, :name, :camel_case) == nil
    end

    test "returns nil for non-builtin formatter" do
      # Only camel/snake/pascal are pre-computed at compile time. MFA tuples
      # and any other formatter shape fall through to the runtime path.
      assert Info.get_formatted_field(PlainResource, :first_name, {SomeMod, :format}) == nil
    end

    test "collects public attributes" do
      assert Info.get_formatted_field(ResourceWithAllKinds, :first_name, :camel_case) ==
               "firstName"
    end

    test "collects public relationships" do
      assert Info.get_formatted_field(ResourceWithAllKinds, :linked_resources, :camel_case) ==
               "linkedResources"
    end

    test "collects public calculations" do
      assert Info.get_formatted_field(ResourceWithAllKinds, :display_name, :camel_case) ==
               "displayName"
    end

    test "collects public aggregates" do
      assert Info.get_formatted_field(ResourceWithAllKinds, :linked_count, :camel_case) ==
               "linkedCount"
    end
  end

  describe "format_field_for_client/3 precedence" do
    test "uses persisted state for resource without callback (fast path)" do
      assert FieldFormatter.format_field_for_client(:first_name, PlainResource, :camel_case) ==
               "firstName"

      assert FieldFormatter.format_field_for_client(:address_line_1, PlainResource, :camel_case) ==
               "addressLine1"
    end

    test "callback takes priority over persisted DSL state" do
      # ResourceWithCallback has BOTH field_names DSL AND a typescript_field_names/0
      # callback. The callback must win.
      assert FieldFormatter.format_field_for_client(
               :is_active?,
               ResourceWithCallback,
               :camel_case
             ) == "isActiveFromCallback"
    end

    test "callback path falls through to formatter for fields not in callback map" do
      # `:first_name` is NOT in the callback's typescript_field_names list, so
      # the callback path falls through to format_field_name/2 — NOT to the DSL.
      # This matches the documented behavior in compute_field_for_client/3.
      assert FieldFormatter.format_field_for_client(
               :first_name,
               ResourceWithCallback,
               :camel_case
             ) == "firstName"
    end

    test "non-typescript resource falls through to plain formatter" do
      assert FieldFormatter.format_field_for_client(:name, NonTypescriptResource, :camel_case) ==
               "name"
    end
  end
end
