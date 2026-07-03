defmodule AshTypescript.Manifest.EntrypointActionDecorationTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.Custom

  @manifest AshTypescript.Test.ApiSpec

  test "entrypoint actions in action_lookup carry precomputed decoration" do
    action_lookup = AshTypescript.action_lookup(@manifest)
    refute action_lookup == %{}

    # Every action reachable via an entrypoint must be decorated (that is the
    # only set the runtime pipeline looks up), so no runtime cache misses.
    decorated =
      Enum.filter(action_lookup, fn {_key, action} ->
        Custom.action_return_classification(action) != nil
      end)

    assert length(decorated) == map_size(action_lookup),
           "expected all #{map_size(action_lookup)} entrypoint actions decorated, got #{length(decorated)}"

    # input maps present per built-in formatter + field types
    Enum.each(action_lookup, fn {_key, action} ->
      assert is_map(Custom.action_input_expected_keys(action, :camel_case))
      assert is_map(Custom.action_input_expected_keys(action, :pascal_case))
      assert is_map(Custom.action_input_expected_keys(action, :snake_case))
      assert Custom.action_input_expected_keys(action, {SomeMod, :fun}) == nil
      assert is_map(Custom.action_input_field_types(action))
    end)
  end

  test "custom field-name mappings take precedence over the formatter in every cached formatter map" do
    action = Map.get(AshTypescript.action_lookup(@manifest), {AshTypescript.Test.User, :create})
    assert action, "expected {User, :create} to be an entrypoint action"

    # `:address_line_1` is mapped to "addressLine1" via the field_names DSL. The
    # mapping must win regardless of formatter, so the client key is identical
    # across all three built-in formatter maps (never "address_line_1"/"AddressLine1").
    for formatter <- [:camel_case, :snake_case, :pascal_case] do
      keys = Custom.action_input_expected_keys(action, formatter)
      assert Map.get(keys, "addressLine1") == :address_line_1
      refute Map.has_key?(keys, "address_line_1")
      refute Map.has_key?(keys, "AddressLine1")
    end

    # An unmapped attribute (`:is_super_admin`) still follows the formatter.
    camel = Custom.action_input_expected_keys(action, :camel_case)
    snake = Custom.action_input_expected_keys(action, :snake_case)
    pascal = Custom.action_input_expected_keys(action, :pascal_case)
    assert Map.get(camel, "isSuperAdmin") == :is_super_admin
    assert Map.get(snake, "is_super_admin") == :is_super_admin
    assert Map.get(pascal, "IsSuperAdmin") == :is_super_admin
  end

  test "cached classification equals a live recompute" do
    type_lookup = AshTypescript.type_lookup(@manifest)

    Enum.each(AshTypescript.action_lookup(@manifest), fn {_key, action} ->
      cached = Custom.action_return_classification(action)

      live =
        AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection.compute_action_returns_field_selectable_type?(
          action,
          type_lookup
        )

      assert cached == live
    end)
  end
end
