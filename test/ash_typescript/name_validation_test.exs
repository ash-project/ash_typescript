# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.NameValidationTest do
  # The rule table: each rule is a pure function of one name, so each verdict
  # is a row here. A test named `[file: case]` carries over that old test
  # case's names and verdicts; the other tests cover rules no old test covered
  # and the spec's rule cases. Where a name sits in the manifest is tested by
  # `AshTypescript.Manifest.NameCheckTest`.
  use ExUnit.Case, async: true

  alias AshTypescript.NameValidation

  # A row's client `:fmt` is the name the default formatter makes from `raw`.
  defp client(raw, :fmt), do: AshRpc.FieldFormatter.format_field_name(raw, :camel_case)
  defp client(_raw, client) when is_binary(client), do: client

  defp assert_client_rows(rows) do
    for {raw, client, explicit?, expected} <- rows do
      name = client(raw, client)

      assert NameValidation.check_client_name(raw, name, explicit?) == expected,
             "check_client_name(#{inspect(raw)}, #{inspect(name)}, #{explicit?})"
    end
  end

  defp assert_binding_rows(rows) do
    for {name, role, expected} <- rows do
      assert NameValidation.check_binding_name(name, role) == expected,
             "check_binding_name(#{inspect(name)}, #{inspect(role)})"
    end
  end

  defp assert_raw_rows(rows) do
    for {raw, expected} <- rows do
      assert NameValidation.check_raw_binding_name(raw) == expected,
             "check_raw_binding_name(#{inspect(raw)})"
    end
  end

  defp assert_alias_rows(rows) do
    for {name, subject, expected} <- rows do
      assert NameValidation.check_alias_name(name, subject) == expected,
             "check_alias_name(#{inspect(name)}, #{inspect(subject)})"
    end
  end

  @not_identifier {:error, :not_identifier}
  @digit {:error, :digit_after_underscore}
  @reserved {:error, :reserved_word}
  @type_keyword {:error, :type_keyword}
  @invalid_raw {:error, :invalid_raw_name}

  # Moved unchanged from resource/verify_field_names_test.exs.
  describe "invalid_name?/1" do
    test "detects question marks in names" do
      assert NameValidation.invalid_name?(:has_review?)
      assert NameValidation.invalid_name?(:is_active?)
      assert NameValidation.invalid_name?("has_review?")
    end

    test "detects underscores followed by numbers" do
      assert NameValidation.invalid_name?(:field_1)
      assert NameValidation.invalid_name?(:address_line_1)
      assert NameValidation.invalid_name?("item_2")
    end

    test "allows valid names" do
      refute NameValidation.invalid_name?(:has_review)
      refute NameValidation.invalid_name?(:is_active)
      refute NameValidation.invalid_name?(:field1)
      refute NameValidation.invalid_name?(:addressLine1)
    end
  end

  describe "field_names_key?/1" do
    test "a name with a question mark or an underscore before a digit can be mapped" do
      assert NameValidation.field_names_key?(:is_active?)
      assert NameValidation.field_names_key?(:address_line_1)
    end

    test "a name that isn't an identifier can be mapped" do
      assert NameValidation.field_names_key?(:"attr-dash")
      assert NameValidation.field_names_key?(:"1st")
    end

    test "any other name can't be" do
      refute NameValidation.field_names_key?(:is_active)
      refute NameValidation.field_names_key?(:line1)
    end
  end

  describe "check_client_name/3, from resource/verify_field_names_test.exs" do
    test "[verify_field_names_test: rejects calculation with question mark when no field_names mapping exists]" do
      assert_client_rows([{:has_review?, :fmt, false, @not_identifier}])
    end

    test "[verify_field_names_test: accepts calculation with question mark when field_names mapping exists]" do
      assert_client_rows([{:has_review?, "hasReview", true, :ok}])
    end

    test "[verify_field_names_test: rejects attribute with underscore number when no field_names mapping exists]" do
      assert_client_rows([{:address_line_1, :fmt, false, @digit}])
    end

    test "[verify_field_names_test: accepts attribute with underscore number when field_names mapping exists]" do
      assert_client_rows([{:address_line_1, "addressLine1", true, :ok}])
    end

    test "[verify_field_names_test: rejects aggregate with question mark when no field_names mapping exists]" do
      assert_client_rows([{:has_items?, :fmt, false, @not_identifier}])
    end

    test "[verify_field_names_test: rejects union member with question mark]" do
      assert_client_rows([{:has_html?, :fmt, false, @not_identifier}])
    end

    test "[verify_field_names_test: rejects union member with underscore number]" do
      assert_client_rows([{:html_1, :fmt, false, @digit}])
    end

    test "[verify_field_names_test: accepts valid union member names]" do
      assert_client_rows(for raw <- [:text, :html, :markdown], do: {raw, :fmt, false, :ok})
    end
  end

  describe "check_client_name/3, from resource/verify_map_field_names_test.exs" do
    test "[verify_map_field_names_test: detects invalid field names in map type constraints]" do
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_active?, :fmt, false, @not_identifier}
      ])
    end

    test "[verify_map_field_names_test: detects invalid field names in keyword type constraints]" do
      assert_client_rows([
        {:setting_1, :fmt, false, @digit},
        {:enabled?, :fmt, false, @not_identifier}
      ])
    end

    test "[verify_map_field_names_test: detects invalid field names in tuple type constraints]" do
      assert_client_rows([{:value_1, :fmt, false, @digit}, {:value_2, :fmt, false, @digit}])
    end

    test "[verify_map_field_names_test: detects invalid field names in union type members]" do
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[verify_map_field_names_test: detects invalid field names in calculation return types]" do
      assert_client_rows([
        {:result_1, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[verify_map_field_names_test: detects invalid field names inside array-of-map field constraints]" do
      assert_client_rows([
        {:entry_1, :fmt, false, @digit},
        {:is_pinned?, :fmt, false, @not_identifier}
      ])
    end

    test "[verify_map_field_names_test: detects invalid field names a NewType callback does not remap]" do
      assert_client_rows([
        {:unmapped_2, :fmt, false, @digit},
        {:mapped_1, "mapped1", true, :ok}
      ])
    end

    test "[verify_map_field_names_test: passes when a NewType callback remaps every invalid field name]" do
      assert_client_rows([
        {:field_1, "field1", true, :ok},
        {:is_active?, "isActive", true, :ok}
      ])
    end
  end

  describe "check_client_name/3, from resource/verify_nested_map_field_names_test.exs" do
    test "[verify_nested_map_field_names_test: detects invalid field names in nested map within map]" do
      assert_client_rows([
        {:inner_field_1, :fmt, false, @digit},
        {:is_nested?, :fmt, false, @not_identifier},
        {:valid_field, :fmt, false, :ok}
      ])
    end

    test "[verify_nested_map_field_names_test: detects invalid field names in nested keyword within map]" do
      assert_client_rows([
        {:option_1, :fmt, false, @digit},
        {:enabled?, :fmt, false, @not_identifier}
      ])
    end

    test "[verify_nested_map_field_names_test: detects invalid field names in union member within map]" do
      assert_client_rows([
        {:text_field_1, :fmt, false, @digit},
        {:alt_text_2, :fmt, false, @digit},
        {:is_bold?, :fmt, false, @not_identifier},
        {:url, :fmt, false, :ok}
      ])
    end

    test "[verify_nested_map_field_names_test: detects invalid field names in deeply nested structures]" do
      assert_client_rows([
        {:deep_field_1, :fmt, false, @digit},
        {:is_deep?, :fmt, false, @not_identifier}
      ])
    end
  end

  describe "check_client_name/3, from typed_controller/verify_typed_controller_test.exs" do
    test "[verify_typed_controller_test: rejects argument names with underscore-number patterns]" do
      assert_client_rows([{:line_1, :fmt, false, @digit}])
    end

    test "[verify_typed_controller_test: rejects argument names with question marks]" do
      assert_client_rows([{:is_active?, :fmt, false, @not_identifier}])
    end

    test "[verify_typed_controller_test: suggests better names in error message]" do
      assert_client_rows([{:address_line_1, :fmt, false, @digit}])
    end

    test "[verify_typed_controller_test: rejects returns field names with question marks]" do
      assert_client_rows([
        {:is_active?, :fmt, false, @not_identifier},
        {:label, :fmt, false, :ok}
      ])
    end

    test "[verify_typed_controller_test: rejects field names nested in arrays and typed maps, reporting their path]" do
      assert_client_rows([{:line_1, :fmt, false, @digit}, {:address, :fmt, false, :ok}])
    end

    test "[verify_typed_controller_test: rejects invalid field names in argument types]" do
      assert_client_rows([{:is_on?, :fmt, false, @not_identifier}])
    end

    test "[verify_typed_controller_test: honors typescript_field_names on types, rejecting only unmapped invalid names]" do
      assert_client_rows([
        {:is_on?, :fmt, false, @not_identifier},
        {:completed?, "completed", true, :ok},
        {:is_urgent?, "isUrgent", true, :ok},
        {:total_count, :fmt, false, :ok}
      ])
    end

    test "[verify_typed_controller_test: points at the mapping when a mapped field name is invalid]" do
      assert_client_rows([{:ok, "ok?", true, @not_identifier}])
    end

    test "[verify_typed_controller_test: rejects field names that are not valid identifiers]" do
      assert_client_rows([
        {:"1st", :fmt, false, @not_identifier},
        {:"foo-bar", :fmt, false, @not_identifier},
        {:"with space", :fmt, false, @not_identifier},
        {:fine, :fmt, false, :ok}
      ])
    end

    test "[verify_typed_controller_test: rejects argument names that are not valid identifiers]" do
      assert_client_rows([{:"foo-bar", :fmt, false, @not_identifier}])
    end
  end

  describe "check_client_name/3, from cases settled after Phase 2" do
    test "[custom_ash_type_test: custom Ash.Type with constraints callback can define field structure]" do
      assert_client_rows([
        {:setting_1, :fmt, false, @digit},
        {:enabled?, :fmt, false, @not_identifier}
      ])
    end

    test "[codegen_enforcement_test: VerifierChecker reports typed controller verifier failures]" do
      assert_client_rows([{:done?, :fmt, false, @not_identifier}])
    end

    test "[codegen_enforcement_test: codegen fails for a manifest typed controller with invalid names]" do
      assert_client_rows([{:done?, :fmt, false, @not_identifier}])
    end

    test "[typescript_field_names_test: VerifyMapFieldNames suggests NewType with typescript_field_names for invalid names]" do
      # Walk: W-c3 (an inline map attribute's fields are type_field slots).
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_active?, :fmt, false, @not_identifier}
      ])
    end
  end

  describe "check_client_name/3, from manifest/custom_types_dsl_test.exs" do
    test "[custom_types_dsl_test: a client_name that isn't a TypeScript identifier is rejected]" do
      assert_client_rows([{:hex, "hex-code", true, @not_identifier}])
    end
  end

  describe "check_client_name/3, from rpc/verify_metadata_field_names_test.exs" do
    test "[verify_metadata_field_names_test: detects metadata fields with underscores followed by digits]" do
      assert_client_rows([{:field_1, :fmt, false, @digit}, {:valid_field, :fmt, false, :ok}])
    end

    test "[verify_metadata_field_names_test: detects metadata fields with question marks]" do
      assert_client_rows([
        {:is_valid?, :fmt, false, @not_identifier},
        {:status, :fmt, false, :ok}
      ])
    end

    test "[verify_metadata_field_names_test: detects metadata fields with combined invalid patterns]" do
      # `field_1?` breaks both rules and gets the first reason only.
      assert_client_rows([
        {:field_1?, :fmt, false, @not_identifier},
        {:item__2, :fmt, false, @digit}
      ])
    end

    test "[verify_metadata_field_names_test: detects invalid TypeScript names even after mapping]" do
      # The deliberate flip (decision readability-rule): an explicit name is
      # checked only for validity.
      assert_client_rows([{:field_a, "field_1", true, :ok}])
    end
  end

  describe "check_client_name/3, from rpc/verify_action_types/" do
    test "[argument_type_field_names_test: detects invalid field names in map argument type]" do
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[argument_type_field_names_test: detects invalid field names in union argument type]" do
      assert_client_rows([{:value_1, :fmt, false, @digit}])
    end

    test "[argument_type_field_names_test: detects invalid field names in array of maps argument type]" do
      assert_client_rows([{:item_1, :fmt, false, @digit}])
    end

    test "[composite_type_test: detects invalid field names in composite type return]" do
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_active?, :fmt, false, @not_identifier},
        {:value_2, :fmt, false, @digit}
      ])
    end

    test "[composite_type_test: detects invalid field names in composite type used as argument]" do
      assert_client_rows([
        {:arg_1, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[composite_type_test: detects invalid field names in nested composite types]" do
      assert_client_rows([
        {:inner_1, :fmt, false, @digit},
        {:is_nested?, :fmt, false, @not_identifier}
      ])
    end

    test "[composite_type_test: a bad field name from typescript_field_names/0 in declared fields]" do
      # `typescript_field_names/0` maps `label` to "label_1": an explicit
      # name, checked only for validity under decision readability-rule, so
      # this verdict differs from the old check's.
      assert_client_rows([{:label, "label_1", true, :ok}])
    end

    test "[composite_type_test: a bad client_name in a manifest map entry]" do
      # `client_name: "label_1"`: explicit, so valid (decision readability-rule).
      assert_client_rows([{:label, "label_1", true, :ok}])
    end

    test "[composite_type_test: a TypedStruct inside a composite-derived field is name-checked]" do
      assert_client_rows([{:x_1, :fmt, false, @digit}])
    end

    test "[custom_ash_type_test: composite custom Ash.Type with invalid field names in composite_types]" do
      assert_client_rows([{:x_1, :fmt, false, @digit}, {:y_2, :fmt, false, @digit}])
    end

    test "[mapped_field_names_test: rejects a mapping that isn't a TypeScript identifier on a resource attribute]" do
      assert_client_rows([{:hex_code, "hex-code", true, @not_identifier}])
    end

    test "[mapped_field_names_test: is reported under the struct module]" do
      assert_client_rows([{:hex_code, "hex-code", true, @not_identifier}])
    end

    test "[mapped_field_names_test: is reported by the manifest too]" do
      assert_client_rows([{:hex_code, "hex-code", true, @not_identifier}])
    end

    test "[mapped_field_names_test: is reported once, under the entrypoint]" do
      assert_client_rows([{:hex_code, "hex-code", true, @not_identifier}])
    end

    test "[mapped_field_names_test: points to the entry's client_name, not typescript_field_names/0]" do
      assert_client_rows([{:is_on?, :fmt, false, @not_identifier}])
    end

    test "[mapped_field_names_test: keeps the typescript_field_names/0 hint for a type without one]" do
      assert_client_rows([{:is_on?, :fmt, false, @not_identifier}])
    end

    test "[mapped_field_names_test: rejects a formatter-made name that isn't valid on a resource attribute]" do
      assert_client_rows([{:is_on?, :fmt, false, @not_identifier}])
    end

    test "[mapped_field_names_test: accepts the field with a client_name that is a TypeScript identifier]" do
      assert_client_rows([{:is_on?, "isOn", true, :ok}])
    end

    test "[new_type_return_types_test: detects invalid field names in Ash.TypedStruct returned by generic action]" do
      assert_client_rows([
        {:completed?, :fmt, false, @not_identifier},
        {:is_urgent?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_return_types_test: detects invalid field names in NewType-based custom type as argument]" do
      assert_client_rows([
        {:setting_1, :fmt, false, @digit},
        {:option_2, :fmt, false, @digit},
        {:enabled?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_return_types_test: detects invalid field names in nested NewType-based custom types]" do
      assert_client_rows([{:value_1, :fmt, false, @digit}, {:count_2, :fmt, false, @digit}])
    end

    test "[new_type_return_types_test: detects invalid field names in array of NewType-based custom type]" do
      assert_client_rows([
        {:item_id_1, :fmt, false, @digit},
        {:quantity_2, :fmt, false, @digit},
        {:in_stock?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_wrapping_test: detects invalid field names in NewType wrapping Map]" do
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_wrapping_test: detects invalid field names in NewType wrapping Keyword]" do
      assert_client_rows([
        {:setting_1, :fmt, false, @digit},
        {:enabled?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_wrapping_test: detects invalid field names in NewType wrapping Tuple]" do
      assert_client_rows([
        {:coord_1, :fmt, false, @digit},
        {:coord_2, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_wrapping_test: detects invalid field names in NewType used as argument type]" do
      assert_client_rows([
        {:value_1, :fmt, false, @digit},
        {:active?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_wrapping_test: detects invalid field names in array of NewType]" do
      assert_client_rows([
        {:item_1, :fmt, false, @digit},
        {:is_done?, :fmt, false, @not_identifier}
      ])
    end

    test "[new_type_wrapping_test: detects invalid field names in nested NewTypes within union]" do
      assert_client_rows([
        {:nested_1, :fmt, false, @digit},
        {:has_value?, :fmt, false, @not_identifier},
        {:error_code, :fmt, false, :ok}
      ])
    end

    # The rule still rejects these names; the cases flipped because a
    # returned resource without the extension has no slots.
    test "[resource_return_types_test: accepts a regular Ash resource returned by generic action: a returned resource without the extension has no name slots (spec Other failures)]" do
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[resource_return_types_test: accepts an array of regular Ash resources: a returned resource without the extension has no name slots (spec Other failures)]" do
      assert_client_rows([{:item_1, :fmt, false, @digit}])
    end

    test "[return_type_field_names_test: detects invalid field names in map return type]" do
      assert_client_rows([
        {:field_1, :fmt, false, @digit},
        {:is_valid?, :fmt, false, @not_identifier}
      ])
    end

    test "[return_type_field_names_test: detects a typescript_field_names mapping that isn't a TypeScript identifier]" do
      assert_client_rows([{:hex_code, "hex-code", true, @not_identifier}])
    end

    test "[return_type_field_names_test: detects invalid field names in keyword return type]" do
      assert_client_rows([
        {:setting_1, :fmt, false, @digit},
        {:enabled?, :fmt, false, @not_identifier}
      ])
    end

    test "[return_type_field_names_test: detects invalid field names in tuple return type]" do
      assert_client_rows([{:value_1, :fmt, false, @digit}, {:value_2, :fmt, false, @digit}])
    end

    test "[return_type_field_names_test: detects invalid field names in union return type members]" do
      assert_client_rows([
        {:result_1, :fmt, false, @digit},
        {:error_code?, :fmt, false, @not_identifier}
      ])
    end

    test "[return_type_field_names_test: detects invalid field names in array of maps return type]" do
      assert_client_rows([
        {:item_1, :fmt, false, @digit},
        {:active?, :fmt, false, @not_identifier}
      ])
    end
  end

  describe "check_client_name/3, old rules no test covered" do
    test "a formatter-made action argument with an underscore before a digit (VerifyRpc)" do
      assert_client_rows([{:filter_1, :fmt, false, @digit}])
    end

    test "a formatter-made accepted attribute with an underscore before a digit (VerifyRpc)" do
      assert_client_rows([{:priority_1, :fmt, false, @digit}])
    end

    test "a field_names value that isn't an identifier (VerifyMappedFieldNames)" do
      assert_client_rows([{:is_done?, "is-done", true, @not_identifier}])
    end

    test "an explicit argument_names value with an underscore before a digit is valid" do
      # VerifyRpc rejected it; the deliberate change of decision readability-rule.
      assert_client_rows([{:is_on?, "is_on_1", true, :ok}])
    end
  end

  describe "check_client_name/3, the spec's rule cases" do
    test "an explicit name with an underscore before a digit is valid" do
      assert_client_rows([{:line_1, "line_1", true, :ok}])
    end

    test "a name breaking both rules gets one reason, not_identifier" do
      assert_client_rows([{:line_1?, :fmt, false, @not_identifier}])
    end

    test "the probe's gaps are not identifiers" do
      assert_client_rows([
        {:attr_dash, "attr-dash", true, @not_identifier},
        {:calc_arg?, :fmt, false, @not_identifier},
        {:"m2-dash", :fmt, false, @not_identifier}
      ])
    end
  end

  describe "check_binding_name/2 and check_raw_binding_name/1, from verify_typed_controller_test.exs" do
    test "[verify_typed_controller_test: rejects route names with underscore-number patterns]" do
      assert_raw_rows([{:step_1, @invalid_raw}])
    end

    test "[verify_typed_controller_test: rejects a route whose function name is a reserved word]" do
      assert_binding_rows(for name <- ["delete", "new", "import"], do: {name, :value, @reserved})
    end

    test "[verify_typed_controller_test: accepts names that contain a reserved word or are TypeScript type keywords]" do
      assert_binding_rows(
        for name <- ["importUsers", "deleteItem", "string"], do: {name, :value, :ok}
      )
    end
  end

  describe "check_binding_name/2, from rpc/verify_rpc_options_test.exs" do
    test "[verify_rpc_options_test: rejects an rpc_action whose function name is a reserved word]" do
      assert_binding_rows([{"delete", :value, @reserved}])
    end

    test "[verify_rpc_options_test: rejects a typed_query whose fields const name is a reserved word]" do
      assert_binding_rows([{"new", :value, @reserved}])
    end

    test "[verify_rpc_options_test: accepts a reserved typed_query name with a valid ts_fields_const_name]" do
      assert_binding_rows([{"newFields", :value, :ok}])
    end

    test "[verify_rpc_options_test: accepts names that contain a reserved word or are TypeScript type keywords]" do
      assert_binding_rows([{"importUsers", :value, :ok}])
    end
  end

  describe "check_binding_name/2 and check_raw_binding_name/1, old rules no test covered" do
    test "an rpc_action or typed_query raw name with ? or an underscore before a digit (VerifyRpc)" do
      assert_raw_rows([
        {:list_1, @invalid_raw},
        {:done?, @invalid_raw},
        {:report_2, @invalid_raw},
        {:list_todos, :ok}
      ])
    end

    test "a route function name that isn't an identifier (VerifyTypedController)" do
      assert_binding_rows([{"foo-bar", :value, @not_identifier}])
    end
  end

  describe "usable_raw_binding_name?/1" do
    test "a raw name the generated code can use as is" do
      assert NameValidation.usable_raw_binding_name?(:list_todos)
      refute NameValidation.usable_raw_binding_name?(:list_1)
      refute NameValidation.usable_raw_binding_name?(:"list-todos")
      refute NameValidation.usable_raw_binding_name?(:delete)
    end
  end

  describe "check_binding_name/2, the spec's rule cases" do
    test "a bare name that isn't an identifier" do
      assert_binding_rows([
        {"list-todos", :value, @not_identifier},
        {"dash-board", :value, @not_identifier}
      ])
    end

    test "a derived name that isn't an identifier" do
      assert_binding_rows([
        {"validateList-todos", :value, @not_identifier},
        {"login-schema", :value, @not_identifier}
      ])
    end

    test "reserved words apply to every binding name, values and types (D2)" do
      assert_binding_rows([
        {"delete", :value, @reserved},
        {"delete", :type, @reserved},
        {"class", :value, @reserved},
        {"deleteItem", :value, :ok},
        {"DeleteInput", :type, :ok}
      ])
    end

    test "a type name can't be a predefined TypeScript type name (D2)" do
      assert_binding_rows(
        for(
          name <- ~w(string any never unknown object number boolean bigint symbol undefined),
          do: {name, :type, @type_keyword}
        ) ++ [{"string", :value, :ok}, {"StringResult", :type, :ok}]
      )
    end

    test "a key is only checked for being an identifier (D4)" do
      assert_binding_rows([
        {"post_created", :key, :ok},
        {"default", :key, :ok},
        {"string", :key, :ok},
        {"post-created", :key, @not_identifier}
      ])
    end

    test "a name breaking both rules gets one reason, not_identifier" do
      assert_binding_rows([{"de-lete", :value, @not_identifier}])
    end
  end

  defp alias_rows(names, subject_of, sentence) do
    for name <- names do
      subject = subject_of.(name)
      {name, subject, {:error, {:alias, "#{subject} #{sentence}"}}}
    end
  end

  @not_ts_identifier "is not a TypeScript identifier."
  @ts_reserved "is a TypeScript reserved word."
  @ts_global "is a global TypeScript name the generated code uses."

  defp ts_alias_of(module), do: &"The ts_alias #{inspect(&1)} of #{module}"

  defp callback_result_of(module),
    do: &"The typescript_type_alias/0 result #{inspect(&1)} of #{module}"

  @configurable "AshTypescript.Manifest.CustomTypeNamesTest.Configurable"

  describe "check_alias_name/2, from manifest/custom_type_names_test.exs" do
    test "[custom_type_names_test: a name that isn't a TypeScript identifier is a DslError]" do
      assert_alias_rows(
        alias_rows(
          ["Geo-Coordinates", "1abc"],
          ts_alias_of("SomeLib.Coordinates"),
          @not_ts_identifier
        )
      )
    end

    test "[custom_type_names_test: a name with a trailing newline is not an identifier]" do
      assert_alias_rows(
        alias_rows(["Shade\n"], ts_alias_of("SomeLib.Coordinates"), @not_ts_identifier)
      )
    end

    test "[custom_type_names_test: await, eval and arguments are rejected]" do
      assert_alias_rows(
        alias_rows(
          ["await", "eval", "arguments"],
          ts_alias_of("SomeLib.Coordinates"),
          @ts_reserved
        )
      )
    end

    test "[custom_type_names_test: a TypeScript type keyword is rejected]" do
      assert_alias_rows(alias_rows(["string"], ts_alias_of("SomeLib.Coordinates"), @ts_reserved))
    end

    test "[custom_type_names_test: a global TypeScript name the generated code uses is rejected]" do
      assert_alias_rows(
        alias_rows(
          ~w(Array Record Promise Partial Date URLSearchParams),
          ts_alias_of("SomeLib.Coordinates"),
          @ts_global
        )
      )
    end

    test "[custom_type_names_test: a JavaScript reserved word is rejected]" do
      assert_alias_rows(alias_rows(["default"], ts_alias_of("SomeLib.Coordinates"), @ts_reserved))
    end

    test "[custom_type_names_test: a result that isn't a TypeScript identifier is a DslError]" do
      assert_alias_rows(
        alias_rows(["Geo-Aliased"], callback_result_of(@configurable), @not_ts_identifier)
      )
    end

    test "[custom_type_names_test: a reserved word is a DslError]" do
      assert_alias_rows(alias_rows(["class"], callback_result_of(@configurable), @ts_reserved))
    end

    test "[custom_type_names_test: a global TypeScript name the generated code uses is a DslError]" do
      assert_alias_rows(alias_rows(["Promise"], callback_result_of(@configurable), @ts_global))
    end

    test "[custom_type_names_test: an invalid result is a DslError when the map entry has no ts_alias]" do
      assert_alias_rows(
        alias_rows(["Geo-Aliased"], callback_result_of(@configurable), @not_ts_identifier)
      )
    end

    test "[custom_type_names_test: names/2 raises on an invalid result]" do
      assert_alias_rows(alias_rows(["class"], callback_result_of(@configurable), @ts_reserved))
    end
  end

  describe "check_alias_name/2, from manifest/type_alias_dsl_test.exs" do
    test "[type_alias_dsl_test: an invalid identifier is a DslError]" do
      assert_alias_rows(alias_rows(["E-mail"], ts_alias_of("SomeLib.Email"), @not_ts_identifier))
    end

    test "[type_alias_dsl_test: a reserved word is a DslError]" do
      assert_alias_rows(alias_rows(["string"], ts_alias_of("SomeLib.Email"), @ts_reserved))
    end

    test "[type_alias_dsl_test: a global TypeScript name the generated code uses is a DslError]" do
      assert_alias_rows(alias_rows(["Record"], ts_alias_of("SomeLib.Email"), @ts_global))
    end

    test "[type_alias_dsl_test: a field-less entry's ts_alias is checked]" do
      assert_alias_rows(
        alias_rows(
          ["not-a-name"],
          ts_alias_of("AshTypescript.Manifest.TypeAliasDslTest.Typed"),
          @not_ts_identifier
        )
      )
    end
  end

  describe "check_alias_name/2, from manifest/type_alias_names_test.exs" do
    test "[type_alias_names_test: an invalid callback result is an error for every kind]" do
      assert_alias_rows(
        alias_rows(
          ["bad-name"],
          callback_result_of("AshTypescript.Manifest.TypeAliasNamesTest.BadName"),
          @not_ts_identifier
        )
      )
    end
  end

  describe "check_alias_name/2, valid names" do
    test "an identifier that is no reserved word or generated-code global is valid" do
      assert_alias_rows([
        {"GeoPoint", "The ts_alias \"GeoPoint\" of SomeLib.Geo", :ok},
        {"MapNew", "The ts_alias \"MapNew\" of SomeLib.Map", :ok}
      ])
    end
  end

  describe "suggest_name/1" do
    test "drops the underscore before a digit and the question mark, as make_name_better/1" do
      assert NameValidation.suggest_name(:address_line_1) == "address_line1"
      assert NameValidation.suggest_name(:is_done?) == "is_done"
    end

    test "turns other non-identifier characters into underscores" do
      assert NameValidation.suggest_name(:"due-at") == "due_at"
      assert NameValidation.suggest_name(:"with space") == "with_space"
      assert NameValidation.suggest_name(:"1st") == "_1st"
    end
  end
end
