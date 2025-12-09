# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Domain do
  @moduledoc """
  Test domain for AshTypescript integration testing.

  Defines RPC actions and typed queries for test resources used in
  the AshTypescript test suite to verify TypeScript generation functionality.
  """
  use Ash.Domain,
    otp_app: :ash_typescript,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTypescript.Test.Todo do
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get_by_id
      rpc_action :get_todo_by_id, :get_by_id

      # Test get? option - retrieves single todo by primary key
      rpc_action :get_single_todo, :read, get?: true

      # Test get? with not_found_error?: false - returns null instead of error
      rpc_action :get_single_todo_nullable, :read, get?: true, not_found_error?: false

      # Test get_by with multiple fields - retrieves single todo by user_id and status
      rpc_action :get_todo_by_user_and_status, :read, get_by: [:user_id, :status]

      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :complete_todo, :complete
      rpc_action :set_priority_todo, :set_priority
      rpc_action :update_todo_with_untyped_data, :update_with_untyped_data
      rpc_action :bulk_complete_todo, :bulk_complete
      rpc_action :get_statistics_todo, :get_statistics
      rpc_action :search_todos, :search
      rpc_action :search_paginated_todos, :search_paginated
      rpc_action :list_recent_todos, :list_recent
      rpc_action :list_high_priority_todos, :list_high_priority
      rpc_action :get_keyword_options_todo, :get_keyword_options
      rpc_action :get_coordinates_info_todo, :get_coordinates_info
      rpc_action :get_custom_data_todo, :get_custom_data
      rpc_action :destroy_todo, :destroy
      rpc_action :assign_to_user_todo, :assign_to_user
      rpc_action :assign_to_users_todo, :assign_to_users

      typed_query :list_todos_user_page, :read do
        ts_fields_const_name "listTodosUserPage"
        ts_result_type_name "ListTodosUserPageResult"

        fields [
          :id,
          :title,
          :description,
          :priority,
          :comment_count,
          %{comments: [:id, :content]},
          %{self: %{args: %{prefix: "some prefix"}, fields: [:id, :title, :is_overdue]}}
        ]
      end
    end

    resource AshTypescript.Test.TodoComment do
      rpc_action :list_todo_comments, :read
      rpc_action :create_todo_comment, :create
      rpc_action :update_todo_comment, :update
      rpc_action :destroy_todo_comment, :destroy
    end

    resource AshTypescript.Test.User do
      rpc_action :list_users, :read
      rpc_action :read_with_invalid_arg, :read_with_invalid_arg
      rpc_action :get_by_id, :get_by_id
      rpc_action :create_user, :create
      rpc_action :update_user, :update
      rpc_action :destroy_user, :destroy

      # Test get_by option - retrieves single user by email
      rpc_action :get_user_by_email, :read, get_by: [:email]

      # Test get_by with not_found_error?: false - returns null instead of error
      rpc_action :get_user_by_email_nullable, :read, get_by: [:email], not_found_error?: false

      # Test get_by with explicit not_found_error?: true (same as default)
      rpc_action :get_user_by_email_error, :read, get_by: [:email], not_found_error?: true

      # Test identities: [] for actor-scoped update/destroy actions (no identity required)
      rpc_action :update_me, :update_me, identities: []
      rpc_action :destroy_me, :destroy_me, identities: []

      # Test identities with multiple options (primary key and email identity)
      rpc_action :update_user_by_identity, :update, identities: [:_primary_key, :unique_email]

      # Test identities with only email identity (no primary key)
      rpc_action :update_user_by_email, :update, identities: [:unique_email]

      typed_query :list_users_with_invalid_arg, :read_with_invalid_arg do
        ts_fields_const_name "ListUsersWithInvalidArg"
        ts_result_type_name "ListUsersWithInvalidArgResult"
        fields [:id, :email]
      end
    end

    resource AshTypescript.Test.UserSettings do
      rpc_action :list_user_settings, :read
      rpc_action :get_user_settings, :get_by_user
      rpc_action :create_user_settings, :create
      rpc_action :update_user_settings, :update
      rpc_action :destroy_user_settings, :destroy
    end

    resource AshTypescript.Test.Post

    resource AshTypescript.Test.OrgTodo do
      rpc_action :list_org_todos, :read
      rpc_action :get_org_todo, :get_by_id
      rpc_action :create_org_todo, :create
      rpc_action :update_org_todo, :update
      rpc_action :complete_org_todo, :complete
      rpc_action :set_priority_org_todo, :set_priority
      rpc_action :bulk_complete_org_todo, :bulk_complete
      rpc_action :get_statistics_org_todo, :get_statistics
      rpc_action :search_org_todos, :search
      rpc_action :destroy_org_todo, :destroy
    end

    resource AshTypescript.Test.Task do
      rpc_action :list_tasks, :read
      rpc_action :read_tasks_with_metadata, :read_with_metadata
      rpc_action :create_task, :create
      rpc_action :update_task, :update
      rpc_action :mark_completed_task, :mark_completed
      rpc_action :destroy_task, :destroy
      rpc_action :get_task_stats, :get_task_stats
      rpc_action :list_task_stats, :list_task_stats

      rpc_action :read_tasks_with_mapped_metadata, :read_with_invalid_metadata_names,
        show_metadata: [:meta_1, :is_valid?, :field_2],
        metadata_field_names: [meta_1: "meta1", is_valid?: "isValid", field_2: "field2"]

      rpc_action :read_tasks_with_metadata_all, :read_with_metadata, show_metadata: nil
      rpc_action :read_tasks_with_metadata_false, :read_with_metadata, show_metadata: false
      rpc_action :read_tasks_with_metadata_empty, :read_with_metadata, show_metadata: []
      rpc_action :read_tasks_with_metadata_one, :read_with_metadata, show_metadata: [:some_string]

      rpc_action :read_tasks_with_metadata_two, :read_with_metadata,
        show_metadata: [:some_string, :some_number]

      rpc_action :create_task_metadata_all, :create, show_metadata: nil
      rpc_action :create_task_metadata_false, :create, show_metadata: false
      rpc_action :create_task_metadata_empty, :create, show_metadata: []
      rpc_action :create_task_metadata_one, :create, show_metadata: [:some_string]
      rpc_action :create_task_metadata_two, :create, show_metadata: [:some_string, :some_number]

      rpc_action :update_task_metadata_all, :update, show_metadata: nil
      rpc_action :update_task_metadata_false, :update, show_metadata: false
      rpc_action :update_task_metadata_empty, :update, show_metadata: []
      rpc_action :update_task_metadata_one, :update, show_metadata: [:some_string]
      rpc_action :update_task_metadata_two, :update, show_metadata: [:some_string, :some_number]

      rpc_action :destroy_task_metadata_all, :destroy, show_metadata: nil
      rpc_action :destroy_task_metadata_false, :destroy, show_metadata: false
      rpc_action :destroy_task_metadata_empty, :destroy, show_metadata: []
      rpc_action :destroy_task_metadata_one, :destroy, show_metadata: [:some_string]
      rpc_action :destroy_task_metadata_two, :destroy, show_metadata: [:some_string, :some_number]
    end

    resource AshTypescript.Test.PostComment
    resource AshTypescript.Test.MapFieldResource
    resource AshTypescript.Test.EmptyResource

    resource AshTypescript.Test.Content do
      rpc_action :list_content, :read
      rpc_action :get_content, :get_by_id
      rpc_action :create_content, :create
      rpc_action :update_content, :update
      rpc_action :destroy_content, :destroy
    end

    resource AshTypescript.Test.Article do
      rpc_action :get_important_dates, :get_important_dates
      rpc_action :get_publication_date, :get_publication_date
      rpc_action :create_article_with_optional_hero_image, :create_with_optional_hero_image

      rpc_action :update_article_with_required_hero_image_alt,
                 :update_with_required_hero_image_alt
    end

    resource AshTypescript.Test.Subscription do
      rpc_action :list_subscriptions, :read
      rpc_action :create_subscription, :create
      rpc_action :update_subscription, :update
      rpc_action :destroy_subscription, :destroy

      # Test identity using fields with field_names mappings (is_active? -> isActive)
      # This tests that identity input/output correctly applies field name formatting
      rpc_action :update_subscription_by_user_status, :update, identities: [:by_user_and_status]

      rpc_action :update_subscription_by_identity, :update,
        identities: [:_primary_key, :by_user_and_status]

      rpc_action :destroy_subscription_by_user_status, :destroy, identities: [:by_user_and_status]
    end

    resource AshTypescript.Test.TenantSetting do
      rpc_action :list_tenant_settings, :read
      rpc_action :create_tenant_setting, :create
      rpc_action :update_tenant_setting, :update
      rpc_action :destroy_tenant_setting, :destroy
    end

    # Input parsing stress test resource - covers all edge cases for input formatting
    resource AshTypescript.Test.InputParsing.Resource do
      rpc_action :list_input_parsing, :read
      rpc_action :get_input_parsing, :get_by_id
      rpc_action :create_input_parsing, :create
      rpc_action :create_input_parsing_with_args, :create_with_args
      rpc_action :update_input_parsing, :update
      rpc_action :destroy_input_parsing, :destroy
      rpc_action :search_input_parsing, :search
      rpc_action :process_data_input_parsing, :process_data
      # New actions for exhaustive input parsing coverage
      rpc_action :process_profile_input_parsing, :process_profile
    end

    # Test resource for nested map field formatting bugs
    resource AshTypescript.Test.NestedMapResource do
      rpc_action :list_users_map, :list_users_map
      rpc_action :get_metrics, :get_metrics
      rpc_action :get_nested_stats, :get_nested_stats
    end
  end

  resources do
    resource AshTypescript.Test.Todo
    resource AshTypescript.Test.TodoComment
    resource AshTypescript.Test.User
    resource AshTypescript.Test.UserSettings
    resource AshTypescript.Test.OrgTodo
    resource AshTypescript.Test.Task
    resource AshTypescript.Test.NotExposed
    resource AshTypescript.Test.Post
    resource AshTypescript.Test.PostComment
    resource AshTypescript.Test.NoRelationshipsResource
    resource AshTypescript.Test.EmptyResource
    resource AshTypescript.Test.MapFieldResource
    resource AshTypescript.Test.Content
    resource AshTypescript.Test.Article
    resource AshTypescript.Test.Subscription
    resource AshTypescript.Test.TenantSetting
    resource AshTypescript.Test.InputParsing.Resource
    resource AshTypescript.Test.NestedMapResource
  end
end
