# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.EntrypointActionDecorationTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.Custom

  @manifest AshTypescript.Test.Manifest

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

    # input map (for the configured formatter) + field types
    Enum.each(action_lookup, fn {_key, action} ->
      assert is_map(AshRpc.Manifest.Custom.action_expected_input_keys(action))
      assert is_map(Custom.action_input_field_types(action))
    end)
  end

  test "custom field-name mappings take precedence over the formatter in the cached input map" do
    action = Map.get(AshTypescript.action_lookup(@manifest), {AshTypescript.Test.User, :create})
    assert action, "expected {User, :create} to be an entrypoint action"

    # `:address_line_1` is mapped to "addressLine1" via the field_names DSL; the
    # mapping wins over the formatter.
    keys = AshRpc.Manifest.Custom.action_expected_input_keys(action)
    assert Map.get(keys, "addressLine1") == :address_line_1
    refute Map.has_key?(keys, "address_line_1")

    # An unmapped attribute (`:is_super_admin`) follows the configured formatter.
    assert Map.get(keys, "isSuperAdmin") == :is_super_admin
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
