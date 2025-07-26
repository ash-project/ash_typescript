defmodule AshTypescript.Rpc.PaginationFieldFormattingTest do
  @moduledoc """
  Tests that pagination field names (hasMore, previousPage, nextPage) are properly
  formatted according to the configured output_field_formatter setting.
  """
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.{User, Domain, TestHelpers}

  # Test data setup helpers
  defp create_test_user! do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{
        name: "Test User",
        email: "test@example.com"
      })
      |> Ash.create!(domain: Domain)

    user.id
  end

  defp create_test_todos!(count, user_id) do
    conn = TestHelpers.build_rpc_conn()

    1..count
    |> Enum.map(fn i ->
      # Create todos via RPC to ensure realistic test data
      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "description", "priority"],
        "input" => %{
          "title" => "Test Todo #{i}",
          "description" => "Description for todo #{i}",
          "priority" => "medium",
          "autoComplete" => false,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)

      case result do
        %{success: true, data: todo} ->
          todo

        %{success: false, errors: errors} ->
          raise "Failed to create test todo: #{inspect(errors)}"
      end
    end)
  end


  setup do
    # Store original formatter to restore later
    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    on_exit(fn ->
      if original_output_field_formatter do
        Application.put_env(
          :ash_typescript,
          :output_field_formatter,
          original_output_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end
    end)

    user_id = create_test_user!()
    create_test_todos!(10, user_id)
    conn = TestHelpers.build_rpc_conn()

    %{original_formatter: original_output_field_formatter, conn: conn, user_id: user_id}
  end

  describe "offset pagination field formatting" do
    test "camelCase formatter formats hasMore correctly", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Test offset pagination with limit that should trigger hasMore
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{"results" => _items, "hasMore" => has_more, "limit" => 5, "offset" => 0}
             } = result

      assert is_boolean(has_more)
      assert has_more == true
    end

    test "snake_case formatter formats has_more correctly", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      # Test offset pagination
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{"results" => _items, "has_more" => has_more, "limit" => 5, "offset" => 0}
             } = result

      assert is_boolean(has_more)
      assert has_more == true
    end

    test "pascal_case formatter formats HasMore correctly", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Test offset pagination
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{"Results" => _items, "HasMore" => has_more, "Limit" => 5, "Offset" => 0}
             } = result

      assert is_boolean(has_more)
      assert has_more == true
    end
  end

  describe "keyset pagination field formatting" do
    test "camelCase formatter formats previousPage and nextPage correctly", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Test keyset pagination
      params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 3}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{
                 "results" => _items,
                 "hasMore" => has_more,
                 "previousPage" => previous_page,
                 "nextPage" => next_page
               }
             } = result

      assert is_boolean(has_more)
      assert is_binary(previous_page)
      assert is_binary(next_page)
      assert previous_page != ""
      assert next_page != ""
    end

    test "snake_case formatter formats previous_page and next_page correctly", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      # Test keyset pagination
      params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 3}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{
                 "results" => _items,
                 "has_more" => has_more,
                 "previous_page" => previous_page,
                 "next_page" => next_page
               }
             } = result

      assert is_boolean(has_more)
      assert is_binary(previous_page)
      assert is_binary(next_page)
      assert previous_page != ""
      assert next_page != ""
    end

    test "pascal_case formatter formats PreviousPage and NextPage correctly", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Test keyset pagination
      params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 3}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{
                 "Results" => _items,
                 "HasMore" => has_more,
                 "PreviousPage" => previous_page,
                 "NextPage" => next_page
               }
             } = result

      assert is_boolean(has_more)
      assert is_binary(previous_page)
      assert is_binary(next_page)
      assert previous_page != ""
      assert next_page != ""
    end
  end

  describe "custom formatter support" do
    test "custom formatter function works for pagination fields", %{conn: conn} do
      Application.put_env(
        :ash_typescript,
        :output_field_formatter,
        {__MODULE__, :custom_format}
      )

      # Test offset pagination with custom formatter
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 3, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      # Should have custom_has_more instead of hasMore or has_more
      assert %{
               success: true,
               data: %{
                 "custom_results" => _items,
                 "custom_has_more" => has_more,
                 "custom_limit" => 3,
                 "custom_offset" => 0
               }
             } = result

      assert is_boolean(has_more)
    end
  end

  # Custom formatter function for testing
  def custom_format(field_name) do
    "custom_#{to_string(field_name)}"
  end
end
