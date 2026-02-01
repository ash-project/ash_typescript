# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TestHelpers do
  @moduledoc """
  Common test helpers and utilities for AshTypescript test suite.

  This module provides reusable functions for:
  - Phoenix.Conn setup for RPC testing
  - Common test data creation (users, todos)
  - Field selection validation
  - Common assertion patterns
  """

  import Phoenix.ConnTest
  import Plug.Conn
  import ExUnit.Assertions
  alias AshTypescript.Rpc
  alias AshTypescript.Test.{Content, Domain, Todo, User}

  @doc """
  Creates a properly configured Plug.Conn for RPC testing.

  Returns a Plug.Conn with:
  - ash private data (actor: nil, tenant: nil)
  - context assignment
  """
  def build_rpc_conn do
    build_conn()
    |> put_private(:ash, %{actor: nil})
    |> Ash.PlugHelpers.set_tenant(nil)
    |> assign(:context, %{})
  end

  @doc """
  Creates a test user with standard test data.

  Options:
  - `:name` - User name (default: "Test User")
  - `:email` - User email (default: "test@example.com")
  - `:fields` - Fields to return (default: ["id"])
  - `:via_rpc` - Create via RPC action instead of direct Ash (default: false)

  Returns the created user data.
  """
  def create_test_user(conn_or_opts \\ [], opts \\ [])

  def create_test_user(conn, opts) when is_struct(conn) do
    opts =
      Keyword.merge(
        [
          name: "Test User",
          email: "test@example.com",
          fields: ["id", "name", "email"],
          via_rpc: true
        ],
        opts
      )

    if opts[:via_rpc] do
      create_user_via_rpc(conn, opts)
    else
      create_user_direct(opts)
    end
  end

  def create_test_user(opts, _) when is_list(opts) do
    opts =
      Keyword.merge(
        [
          name: "Test User",
          email: "test@example.com"
        ],
        opts
      )

    create_user_direct(opts)
  end

  @doc """
  Creates a test todo with standard test data.

  Options:
  - `:title` - Todo title (default: "Test Todo")
  - `:user_id` - User ID (required)
  - `:completed` - Completion status (default: false)
  - `:fields` - Fields to return (default: ["id", "title"])
  - `:via_rpc` - Create via RPC action instead of direct Ash (default: false)

  Returns the created todo data.
  """
  def create_test_todo(conn_or_opts \\ [], opts \\ [])

  def create_test_todo(conn, opts) when is_struct(conn) do
    opts =
      Keyword.merge(
        [
          title: "Test Todo",
          completed: false,
          fields: ["id", "title"],
          via_rpc: true
        ],
        opts
      )

    unless opts[:user_id] do
      raise ArgumentError, "user_id is required for creating test todos"
    end

    if opts[:via_rpc] do
      create_todo_via_rpc(conn, opts)
    else
      create_todo_direct(opts)
    end
  end

  def create_test_todo(opts, _) when is_list(opts) do
    opts =
      Keyword.merge(
        [
          title: "Test Todo",
          completed: false
        ],
        opts
      )

    unless opts[:user_id] do
      raise ArgumentError, "user_id is required for creating test todos"
    end

    create_todo_direct(opts)
  end

  @doc """
  Creates a complete test scenario with user and todo.

  Options:
  - `:user_name` - User name (default: "Test User")
  - `:user_email` - User email (default: "test@example.com")
  - `:todo_title` - Todo title (default: "Test Todo")
  - `:todo_completed` - Todo completion status (default: false)
  - `:via_rpc` - Create via RPC actions (default: false)

  Returns `{user, todo}` tuple.
  """
  def create_test_scenario(conn_or_opts \\ [], opts \\ [])

  def create_test_scenario(conn, opts) when is_struct(conn) do
    opts =
      Keyword.merge(
        [
          user_name: "Test User",
          user_email: "test@example.com",
          todo_title: "Test Todo",
          todo_completed: false,
          via_rpc: true
        ],
        opts
      )

    user =
      create_test_user(conn,
        name: opts[:user_name],
        email: opts[:user_email],
        via_rpc: opts[:via_rpc]
      )

    user_id = if opts[:via_rpc], do: user["id"], else: user.id

    todo =
      create_test_todo(conn,
        title: opts[:todo_title],
        completed: opts[:todo_completed],
        user_id: user_id,
        via_rpc: opts[:via_rpc]
      )

    {user, todo}
  end

  def create_test_scenario(opts, _) when is_list(opts) do
    opts =
      Keyword.merge(
        [
          user_name: "Test User",
          user_email: "test@example.com",
          todo_title: "Test Todo",
          todo_completed: false
        ],
        opts
      )

    user =
      create_test_user(
        name: opts[:user_name],
        email: opts[:user_email]
      )

    todo =
      create_test_todo(
        title: opts[:todo_title],
        completed: opts[:todo_completed],
        user_id: user.id
      )

    {user, todo}
  end

  @doc """
  Creates a test content item with an article.

  Options:
  - `:title` - Content title (default: "Test Content")
  - `:user_id` - User ID (author) (required)
  - `:thumbnail_url` - Thumbnail URL (default: "https://example.com/thumb.jpg")
  - `:thumbnail_alt` - Thumbnail alt text (default: "Thumbnail")
  - `:published_at` - Published timestamp (default: nil)
  - `:category` - Content category (default: :nutrition)
  - `:article_hero_image_url` - Article hero image URL (default: "https://example.com/hero.jpg")
  - `:article_hero_image_alt` - Article hero image alt text (default: "Hero Image")
  - `:article_summary` - Article summary (default: "Test summary")
  - `:article_body` - Article body (default: "Test body content")
  - `:fields` - Fields to return (default: ["id", "title"])
  - `:via_rpc` - Create via RPC action instead of direct Ash (default: false)

  Returns the created content data.
  """
  def create_test_content(conn_or_opts \\ [], opts \\ [])

  def create_test_content(conn, opts) when is_struct(conn) do
    opts =
      Keyword.merge(
        [
          title: "Test Content",
          thumbnail_url: "https://example.com/thumb.jpg",
          thumbnail_alt: "Thumbnail",
          published_at: nil,
          category: :nutrition,
          article_hero_image_url: "https://example.com/hero.jpg",
          article_hero_image_alt: "Hero Image",
          article_summary: "Test summary",
          article_body: "Test body content",
          fields: ["id", "title"],
          via_rpc: true
        ],
        opts
      )

    unless opts[:user_id] do
      raise ArgumentError, "user_id is required for creating test content"
    end

    if opts[:via_rpc] do
      create_content_via_rpc(conn, opts)
    else
      create_content_direct(opts)
    end
  end

  def create_test_content(opts, _) when is_list(opts) do
    opts =
      Keyword.merge(
        [
          title: "Test Content",
          thumbnail_url: "https://example.com/thumb.jpg",
          thumbnail_alt: "Thumbnail",
          published_at: nil,
          category: :nutrition,
          article_hero_image_url: "https://example.com/hero.jpg",
          article_hero_image_alt: "Hero Image",
          article_summary: "Test summary",
          article_body: "Test body content"
        ],
        opts
      )

    unless opts[:user_id] do
      raise ArgumentError, "user_id is required for creating test content"
    end

    create_content_direct(opts)
  end

  @doc """
  Validates that a result contains only the requested fields.

  Args:
  - `result` - The result map to validate
  - `expected_fields` - List of expected field names (strings)

  Raises if the result contains unexpected fields.
  """
  def assert_only_requested_fields(result, expected_fields) do
    actual_fields = Map.keys(result) |> Enum.sort()
    expected_sorted = Enum.sort(expected_fields)

    assert actual_fields == expected_sorted,
           "Expected only fields #{inspect(expected_sorted)}, but got #{inspect(actual_fields)}"
  end

  @doc """
  Validates that an RPC action result has the expected success structure.

  Args:
  - `result` - RPC action result
  - `expected_data_check` - Optional function to validate the data (default: &is_map/1)

  Returns the data portion of the result.
  """
  def assert_rpc_success(result, expected_data_check \\ &is_map/1) do
    assert %{"success" => true, "data" => data} = result
    assert expected_data_check.(data), "Data validation failed for: #{inspect(data)}"
    data
  end

  @doc """
  Validates that an RPC action result has the expected error structure.

  Args:
  - `result` - RPC action result

  Returns the error portion of the result.
  """
  def assert_rpc_error(result) do
    assert %{"success" => false, "errors" => error} = result
    error
  end

  @doc """
  Creates application config changes with automatic cleanup.

  Args:
  - `config_changes` - Keyword list of {app, key, value} tuples
  - `test_function` - Function to run with the config changes

  Automatically restores original configuration after the test.
  """
  def with_application_config(config_changes, test_function) do
    # Store original values
    original_values =
      Enum.map(config_changes, fn {app, key, _value} ->
        {app, key, Application.get_env(app, key)}
      end)

    try do
      # Apply new configuration
      Enum.each(config_changes, fn {app, key, value} ->
        Application.put_env(app, key, value)
      end)

      # Run test
      test_function.()
    after
      # Restore original configuration
      Enum.each(original_values, fn {app, key, original_value} ->
        if original_value do
          Application.put_env(app, key, original_value)
        else
          Application.delete_env(app, key)
        end
      end)
    end
  end

  # Private helper functions

  defp create_user_via_rpc(conn, opts) do
    user_params = %{
      "action" => "create_user",
      "fields" => opts[:fields],
      "input" => %{
        "name" => opts[:name],
        "email" => opts[:email]
      }
    }

    result = Rpc.run_action(:ash_typescript, conn, user_params)
    assert_rpc_success(result)
  end

  defp create_user_direct(opts) do
    User
    |> Ash.Changeset.for_create(:create, %{
      name: opts[:name],
      email: opts[:email]
    })
    |> Ash.create!(domain: Domain)
  end

  defp create_todo_via_rpc(conn, opts) do
    # Build base input
    input = %{
      "title" => opts[:title],
      "autoComplete" => opts[:completed],
      "userId" => opts[:user_id]
    }

    # Add any additional input fields (like custom_data)
    input =
      if opts[:custom_data], do: Map.put(input, "customData", opts[:custom_data]), else: input

    todo_params = %{
      "action" => "create_todo",
      "fields" => opts[:fields],
      "input" => input
    }

    result = Rpc.run_action(:ash_typescript, conn, todo_params)
    assert_rpc_success(result)
  end

  defp create_todo_direct(opts) do
    Todo
    |> Ash.Changeset.for_create(:create, %{
      title: opts[:title],
      completed: opts[:completed],
      user_id: opts[:user_id]
    })
    |> Ash.create!(domain: Domain)
  end

  defp create_content_via_rpc(conn, opts) do
    # Build article input - use snake_case as it's passed directly to manage_relationship
    article_input = %{
      "hero_image_url" => opts[:article_hero_image_url],
      "hero_image_alt" => opts[:article_hero_image_alt],
      "summary" => opts[:article_summary],
      "body" => opts[:article_body]
    }

    # Build content input - use camelCase for top-level fields
    input = %{
      "type" => "article",
      "title" => opts[:title],
      "thumbnailUrl" => opts[:thumbnail_url],
      "thumbnailAlt" => opts[:thumbnail_alt],
      "category" => to_string(opts[:category]),
      "userId" => opts[:user_id],
      "item" => article_input
    }

    input =
      if opts[:published_at],
        do: Map.put(input, "publishedAt", opts[:published_at]),
        else: input

    content_params = %{
      "action" => "create_content",
      "fields" => opts[:fields],
      "input" => input
    }

    result = Rpc.run_action(:ash_typescript, conn, content_params)
    assert_rpc_success(result)
  end

  defp create_content_direct(opts) do
    # First create the content (without article relationship initially)
    content =
      Content
      |> Ash.Changeset.for_create(:create, %{
        type: :article,
        title: opts[:title],
        thumbnail_url: opts[:thumbnail_url],
        thumbnail_alt: opts[:thumbnail_alt],
        published_at: opts[:published_at],
        category: opts[:category],
        user_id: opts[:user_id],
        item: %{
          hero_image_url: opts[:article_hero_image_url],
          hero_image_alt: opts[:article_hero_image_alt],
          summary: opts[:article_summary],
          body: opts[:article_body]
        }
      })
      |> Ash.create!(domain: Domain)

    # Reload content to get the relationship
    content
    |> Ash.load!([:article], domain: Domain)
  end
end
