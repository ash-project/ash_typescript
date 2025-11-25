# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RpcInputOptionalityTest do
  @moduledoc """
  Tests for input type optionality based on action configuration.

  This test module verifies that generated input types correctly handle:
  1. `allow_nil_input` on create actions - makes specified attributes optional
  2. `require_attributes` on update actions - makes specified attributes required

  These tests use the Article resource which has:
  - `create_with_optional_hero_image` action with `allow_nil_input: [:hero_image_url]`
  - `update_with_required_hero_image_alt` action with `require_attributes: [:hero_image_alt]`
  """
  use ExUnit.Case, async: true

  setup_all do
    {:ok, generated_content} =
      AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

    {:ok, generated: generated_content}
  end

  describe "create action with allow_nil_input" do
    test "attribute in allow_nil_input is optional even when allow_nil?: false", %{
      generated: generated
    } do
      input_type_match =
        Regex.run(
          ~r/export type CreateArticleWithOptionalHeroImageInput = \{[^}]+\}/s,
          generated
        )

      assert input_type_match, "CreateArticleWithOptionalHeroImageInput type should be defined"

      input_type = List.first(input_type_match)

      # heroImageUrl should be optional (in allow_nil_input)
      # even though the attribute has allow_nil?: false
      assert input_type =~ "heroImageUrl?: string;"
    end

    test "attribute not in allow_nil_input remains required when allow_nil?: false", %{
      generated: generated
    } do
      input_type_match =
        Regex.run(
          ~r/export type CreateArticleWithOptionalHeroImageInput = \{[^}]+\}/s,
          generated
        )

      input_type = List.first(input_type_match)

      # heroImageAlt should be required (not in allow_nil_input, allow_nil?: false)
      assert input_type =~ "heroImageAlt: string;"
      refute input_type =~ "heroImageAlt?: string;"

      # summary and body should also be required
      assert input_type =~ "summary: string;"
      assert input_type =~ "body: string;"
    end
  end

  describe "update action with require_attributes" do
    test "attribute in require_attributes is required", %{generated: generated} do
      input_type_match =
        Regex.run(
          ~r/export type UpdateArticleWithRequiredHeroImageAltInput = \{[^}]+\}/s,
          generated
        )

      assert input_type_match,
             "UpdateArticleWithRequiredHeroImageAltInput type should be defined"

      input_type = List.first(input_type_match)

      # heroImageAlt should be required (in require_attributes)
      assert input_type =~ "heroImageAlt: string;"
      refute input_type =~ "heroImageAlt?: string;"
    end

    test "attribute not in require_attributes is optional for update action", %{
      generated: generated
    } do
      input_type_match =
        Regex.run(
          ~r/export type UpdateArticleWithRequiredHeroImageAltInput = \{[^}]+\}/s,
          generated
        )

      input_type = List.first(input_type_match)

      # heroImageUrl, summary, body should be optional (not in require_attributes)
      assert input_type =~ "heroImageUrl?: string;"
      assert input_type =~ "summary?: string;"
      assert input_type =~ "body?: string;"
    end
  end
end
