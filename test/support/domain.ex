defmodule AshTypescript.Test.Domain do
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
      rpc_action :bulk_complete_todo, :bulk_complete
      rpc_action :get_statistics_todo, :get_statistics
      rpc_action :search_todos, :search
      rpc_action :search_paginated_todos, :search_paginated
      rpc_action :list_recent_todos, :list_recent
      rpc_action :list_high_priority_todos, :list_high_priority
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
      rpc_action :create_user, :create
      rpc_action :update_user, :update
      rpc_action :destroy_user, :destroy
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
  end

  resources do
    resource AshTypescript.Test.Todo
    resource AshTypescript.Test.TodoComment
    resource AshTypescript.Test.User
    resource AshTypescript.Test.UserSettings
    resource AshTypescript.Test.OrgTodo
    resource AshTypescript.Test.NotExposed
    resource AshTypescript.Test.Post
    resource AshTypescript.Test.PostComment
    resource AshTypescript.Test.NoRelationshipsResource
    resource AshTypescript.Test.EmptyResource
  end
end
