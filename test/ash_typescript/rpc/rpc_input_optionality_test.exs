# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RpcInputOptionalityTest do
  @moduledoc """
  Tests for input type optionality based on `allow_nil_input` and `require_attributes`
  action configuration, using the Article resource.
  """
  use ExUnit.Case, async: true

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    {:ok, generated_content} =
      AshTypescript.Test.CodegenTestHelper.generate_all_content()

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

      # heroImageUrl is optional via allow_nil_input even though the attribute has allow_nil?: false
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

      assert input_type =~ "heroImageAlt: string;"
      refute input_type =~ "heroImageAlt?: string;"

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

      assert input_type =~ "heroImageUrl?: string;"
      assert input_type =~ "summary?: string;"
      assert input_type =~ "body?: string;"
    end
  end
end
