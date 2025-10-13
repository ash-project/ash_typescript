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

      # Read action with metadata field name mapping
      rpc_action :read_tasks_with_mapped_metadata, :read_with_invalid_metadata_names,
        show_metadata: [:meta_1, :is_valid?, :field_2],
        metadata_field_names: [meta_1: :meta1, is_valid?: :is_valid, field_2: :field2]

      # Read actions with different show_metadata configurations
      rpc_action :read_tasks_with_metadata_all, :read_with_metadata, show_metadata: nil
      rpc_action :read_tasks_with_metadata_false, :read_with_metadata, show_metadata: false
      rpc_action :read_tasks_with_metadata_empty, :read_with_metadata, show_metadata: []
      rpc_action :read_tasks_with_metadata_one, :read_with_metadata, show_metadata: [:some_string]

      rpc_action :read_tasks_with_metadata_two, :read_with_metadata,
        show_metadata: [:some_string, :some_number]

      # Create actions with different show_metadata configurations
      rpc_action :create_task_metadata_all, :create, show_metadata: nil
      rpc_action :create_task_metadata_false, :create, show_metadata: false
      rpc_action :create_task_metadata_empty, :create, show_metadata: []
      rpc_action :create_task_metadata_one, :create, show_metadata: [:some_string]
      rpc_action :create_task_metadata_two, :create, show_metadata: [:some_string, :some_number]

      # Update actions with different show_metadata configurations
      rpc_action :update_task_metadata_all, :update, show_metadata: nil
      rpc_action :update_task_metadata_false, :update, show_metadata: false
      rpc_action :update_task_metadata_empty, :update, show_metadata: []
      rpc_action :update_task_metadata_one, :update, show_metadata: [:some_string]
      rpc_action :update_task_metadata_two, :update, show_metadata: [:some_string, :some_number]

      # Destroy actions with different show_metadata configurations
      rpc_action :destroy_task_metadata_all, :destroy, show_metadata: nil
      rpc_action :destroy_task_metadata_false, :destroy, show_metadata: false
      rpc_action :destroy_task_metadata_empty, :destroy, show_metadata: []
      rpc_action :destroy_task_metadata_one, :destroy, show_metadata: [:some_string]
      rpc_action :destroy_task_metadata_two, :destroy, show_metadata: [:some_string, :some_number]
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
  end
end
