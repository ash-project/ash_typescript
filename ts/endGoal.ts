/**
 * Advanced TypeScript Type Inference System with Generic Relationship Types
 *
 * This file demonstrates a sophisticated type system that automatically infers
 * the return type of database queries based on the configuration object passed
 * to the query function. It uses a generic, reusable approach for handling
 * relationships between resources.
 *
 * Features:
 * - Automatic type inference based on `select` and `load` configuration
 * - Support for calculated fields (aggregates and computed values)
 * - Generic, reusable relationship types that work across all resources
 * - Infinitely deep relationship loading with circular reference support
 * - Type-safe query building and merging utilities
 * - Pre-defined common query configurations
 * - Runtime validation helpers
 *
 * Key Components:
 *
 * 1. Schema Types:
 *    - TodoSelectSchema, CommentSelectSchema, UserSelectSchema: Base fields for each resource
 *    - TodoCalculatedFieldsSchema, CommentCalculatedFieldsSchema: Computed fields like aggregates
 *
 * 2. Generic Relationship Types:
 *    - TodoRelationship<TConfig>: Handles Todo relationships from any context
 *    - CommentRelationship<TConfig>: Handles Comment relationships from any context
 *    - UserRelationship<TConfig>: Handles User relationships from any context
 *    - CommentLikeRelationship<TConfig>: Handles CommentLike relationships from any context
 *    - Array variants for has_many relationships
 *
 * 3. Circular Reference Support:
 *    Enables infinitely deep queries like: comment.user.comment_likes[0].comment.user.todos[0]
 *
 * Run `npm run test` from this project's `ts` folder to compile and verify types.
 */

type TodoSelectSchema = {
  id: string;
  title: string;
  description: string | null;
  completed: boolean;
  status: "pending" | "ongoing" | "finished" | "cancelled";
  priority: "low" | "medium" | "high" | "urgent";
  due_date: string | null; // ISO date string
  tags: string[];
  metadata: Record<string, any> | null;
  created_at: string; // ISO datetime string
  updated_at: string; // ISO datetime string
};

type TodoCalculatedFieldsSchema = {
  // Aggregates
  comment_count: number;
  helpful_comment_count: number;
  has_comments: boolean;
  average_rating: number | null;
  highest_rating: number | null;
  latest_comment_content: string | null;
  comment_authors: string[];

  // Calculations
  is_overdue: boolean;
  days_until_due: number | null;
};

type TodoRelationshipSchema = {
  user: { select: UserSelectSchema };
  comments: Array<{
    select: CommentSelectSchema;
    load?: CommentRelationshipSchema;
  }>;
};

// Schema definitions for Comment resource
type CommentSelectSchema = {
  id: string;
  content: string;
  author_name: string;
  rating: number | null;
  is_helpful: boolean;
  created_at: string;
  updated_at: string;
};

type CommentCalculatedFieldsSchema = {};

// Schema definitions for CommentLike resource
type CommentLikeSelectSchema = {
  id: string;
};

type CommentLikeRelationshipSchema = {
  user: { select: UserSelectSchema; load?: UserRelationshipSchema };
  comment: { select: CommentSelectSchema; load?: CommentRelationshipSchema };
};

type CommentRelationshipSchema = {
  todo: {
    select: TodoSelectSchema;
    load?: {
      [x in keyof TodoCalculatedFieldsSchema]?: boolean;
    } & TodoRelationshipSchema;
  };
  user: { select: UserSelectSchema; load?: UserRelationshipSchema };
  likes: Array<{
    select: CommentLikeSelectSchema;
    load?: CommentLikeRelationshipSchema;
  }>;
};

// Schema definitions for User resource
type UserSelectSchema = {
  id: string;
  email: string;
};

type UserRelationshipSchema = {
  // Relationships
  comments: Array<CommentSelectSchema>;
  todos: Array<TodoSelectSchema>;
  comment_likes: Array<CommentLikeSelectSchema>;
};

// Utility types for type inference
type PickFields<T, K extends keyof T> = Pick<T, K>;

// Helper to extract calculated fields that are enabled
type ExtractCalculatedFields<TCalc, TLoad> = {
  [K in keyof TLoad]: K extends keyof TCalc
    ? TLoad[K] extends true
      ? K
      : never
    : never;
}[keyof TLoad];

type CalculatedFieldsResult<TCalc, TLoad> = PickFields<
  TCalc,
  ExtractCalculatedFields<TCalc, TLoad>
>;

// Main type for inferring the complete result
// Main type inference for todo query results
type InferTodoQueryResult<TConfig> = TConfig extends {
  select: infer TSelect;
  load?: infer TLoad;
}
  ? TSelect extends readonly (keyof TodoSelectSchema)[]
    ? Array<
        PickFields<TodoSelectSchema, TSelect[number]> &
          (TLoad extends Record<string, any>
            ? CalculatedFieldsResult<TodoCalculatedFieldsSchema, TLoad> &
                (TLoad extends { user: infer TUserConfig }
                  ? { user: UserRelationship<TUserConfig> }
                  : {}) &
                (TLoad extends { comments: infer TCommentsConfig }
                  ? { comments: CommentsArrayRelationship<TCommentsConfig> }
                  : {})
            : {})
      >
    : never
  : never;

// Configuration type with proper constraints
type ReadTodosConfig = {
  select: readonly (keyof TodoSelectSchema)[];
  load?: {
    // Calculated fields
    [K in keyof TodoCalculatedFieldsSchema]?: boolean;
  } & {
    // Relationships
    user?: {
      select: readonly (keyof UserSelectSchema)[];
      load?: {
        comments?: {
          select: readonly (keyof CommentSelectSchema)[];
        };
        todos?: {
          select: readonly (keyof TodoSelectSchema)[];
        };
      };
    };
    comments?: {
      select: readonly (keyof CommentSelectSchema)[];
    };
  };
  filter?: any;
  sort?: any;
  limit?: number;
  offset?: number;
};

function buildReadTodosPayload(config: any) {
  return {
    select: config.select,
    load: config.load,
    filter: config.filter,
    sort: config.sort,
    limit: config.limit,
    offset: config.offset,
  };
}

async function readTodos<const T extends ReadTodosConfig>(
  config: T,
): Promise<InferTodoQueryResult<T>> {
  const payload = buildReadTodosPayload(config);
  const response = await fetch("/api/todos", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return response.json();
}

// Generic reusable relationship inference system
type InferResourceResult<
  TConfig,
  TSelectSchema,
  TCalculatedSchema = {},
  TRelationshipMap = {},
> = TConfig extends {
  select: infer TSelect;
  load?: infer TLoad;
}
  ? TSelect extends readonly (keyof TSelectSchema)[]
    ? PickFields<TSelectSchema, TSelect[number]> &
        (TLoad extends Record<string, any>
          ? PickFields<
              TCalculatedSchema,
              ExtractCalculatedFields<TCalculatedSchema, TLoad>
            > &
              InferRelationshipsFromMap<TLoad, TRelationshipMap>
          : {})
    : never
  : never;

type InferRelationshipsFromMap<TLoad, TRelationshipMap> =
  TLoad extends Record<string, any>
    ? {
        [K in keyof TLoad]: K extends keyof TRelationshipMap
          ? TRelationshipMap[K] extends {
              type: "single";
              target: infer TTarget;
            }
            ? TTarget extends {
                select: any;
                calculated?: any;
                relationships?: any;
              }
              ? InferResourceResult<
                  TLoad[K],
                  TTarget["select"],
                  TTarget["calculated"],
                  TTarget["relationships"]
                >
              : never
            : TRelationshipMap[K] extends {
                  type: "array";
                  target: infer TTarget;
                }
              ? TTarget extends {
                  select: any;
                  calculated?: any;
                  relationships?: any;
                }
                ? InferArrayRelationshipResult<
                    TLoad[K],
                    TTarget["select"],
                    TTarget["calculated"],
                    TTarget["relationships"]
                  >
                : never
              : never
          : never;
      }
    : {};

type InferArrayRelationshipResult<
  TConfig,
  TSelectSchema,
  TCalculatedSchema = {},
  TRelationshipMap = {},
> =
  TConfig extends Array<{
    select: infer TSelect;
    load?: infer TLoad;
  }>
    ? TSelect extends readonly (keyof TSelectSchema)[]
      ? Array<
          PickFields<TSelectSchema, TSelect[number]> &
            (TLoad extends Record<string, any>
              ? PickFields<
                  TCalculatedSchema,
                  ExtractCalculatedFields<TCalculatedSchema, TLoad>
                > &
                  InferRelationshipsFromMap<TLoad, TRelationshipMap>
              : {})
        >
      : never
    : TConfig extends {
          select: infer TSelect;
          load?: infer TLoad;
        }
      ? TSelect extends readonly (keyof TSelectSchema)[]
        ? Array<
            PickFields<TSelectSchema, TSelect[number]> &
              (TLoad extends Record<string, any>
                ? PickFields<
                    TCalculatedSchema,
                    ExtractCalculatedFields<TCalculatedSchema, TLoad>
                  > &
                    InferRelationshipsFromMap<TLoad, TRelationshipMap>
                : {})
          >
        : never
      : never;

// Simplified generic relationship types
// Simplified approach: specific relationship types that handle circular references
type TodoRelationship<TConfig> = TConfig extends {
  select: infer TSelect;
  load?: infer TLoad;
}
  ? TSelect extends readonly (keyof TodoSelectSchema)[]
    ? PickFields<TodoSelectSchema, TSelect[number]> &
        (TLoad extends Record<string, any>
          ? CalculatedFieldsResult<TodoCalculatedFieldsSchema, TLoad> &
              (TLoad extends { user: infer TUserConfig }
                ? { user: UserRelationship<TUserConfig> }
                : {}) &
              (TLoad extends { comments: infer TCommentsConfig }
                ? { comments: CommentsArrayRelationship<TCommentsConfig> }
                : {})
          : {})
    : never
  : never;

type CommentRelationship<TConfig> = TConfig extends {
  select: infer TSelect;
  load?: infer TLoad;
}
  ? TSelect extends readonly (keyof CommentSelectSchema)[]
    ? PickFields<CommentSelectSchema, TSelect[number]> &
        (TLoad extends Record<string, any>
          ? CommentCalculatedFieldsResult<
              CommentCalculatedFieldsSchema,
              TLoad
            > &
              (TLoad extends { todo: infer TTodoConfig }
                ? { todo: TodoRelationship<TTodoConfig> }
                : {}) &
              (TLoad extends { user: infer TUserConfig }
                ? { user: UserRelationship<TUserConfig> }
                : {}) &
              (TLoad extends { likes: infer TLikesConfig }
                ? { likes: CommentLikesArrayRelationship<TLikesConfig> }
                : {})
          : {})
    : never
  : never;

type UserRelationship<TConfig> = TConfig extends {
  select: infer TUserSelect;
  load?: infer TUserLoad;
}
  ? TUserSelect extends readonly (keyof UserSelectSchema)[]
    ? PickFields<UserSelectSchema, TUserSelect[number]> &
        (TUserLoad extends { todos?: infer TTodosConfig }
          ? { todos: TodosArrayRelationship<TTodosConfig> }
          : {}) &
        (TUserLoad extends { comments?: infer TCommentsConfig }
          ? { comments: CommentsArrayRelationship<TCommentsConfig> }
          : {}) &
        (TUserLoad extends { comment_likes?: infer TCommentLikesConfig }
          ? {
              comment_likes: CommentLikesArrayRelationship<TCommentLikesConfig>;
            }
          : {})
    : never
  : never;

type CommentsArrayRelationship<TConfig> = TConfig extends {
  select: infer TSelect;
  load?: infer TLoad;
}
  ? TSelect extends readonly (keyof CommentSelectSchema)[]
    ? Array<
        PickFields<CommentSelectSchema, TSelect[number]> &
          (TLoad extends Record<string, any>
            ? CommentCalculatedFieldsResult<
                CommentCalculatedFieldsSchema,
                TLoad
              > &
                (TLoad extends { todo: infer TTodoConfig }
                  ? { todo: TodoRelationship<TTodoConfig> }
                  : {}) &
                (TLoad extends { user: infer TUserConfig }
                  ? { user: UserRelationship<TUserConfig> }
                  : {}) &
                (TLoad extends { likes: infer TLikesConfig }
                  ? { likes: CommentLikesArrayRelationship<TLikesConfig> }
                  : {})
            : {})
      >
    : never
  : never;

type TodosArrayRelationship<TConfig> = TConfig extends {
  select: infer TSelect;
  load?: infer TLoad;
}
  ? TSelect extends readonly (keyof TodoSelectSchema)[]
    ? Array<
        PickFields<TodoSelectSchema, TSelect[number]> &
          (TLoad extends Record<string, any>
            ? CalculatedFieldsResult<TodoCalculatedFieldsSchema, TLoad> &
                (TLoad extends { user: infer TUserConfig }
                  ? { user: UserRelationship<TUserConfig> }
                  : {}) &
                (TLoad extends { comments: infer TCommentsConfig }
                  ? { comments: CommentsArrayRelationship<TCommentsConfig> }
                  : {})
            : {})
      >
    : never
  : never;

type CommentLikesArrayRelationship<TConfig> =
  TConfig extends Array<{ select: infer TSelect; load?: infer TLoad }>
    ? TSelect extends readonly (keyof CommentLikeSelectSchema)[]
      ? Array<
          PickFields<CommentLikeSelectSchema, TSelect[number]> &
            (TLoad extends { user?: infer TUserConfig }
              ? { user: UserRelationship<TUserConfig> }
              : {}) &
            (TLoad extends { comment?: infer TCommentConfig }
              ? { comment: CommentRelationship<TCommentConfig> }
              : {})
        >
      : never
    : TConfig extends { select: infer TSelect; load?: infer TLoad }
      ? TSelect extends readonly (keyof CommentLikeSelectSchema)[]
        ? Array<
            PickFields<CommentLikeSelectSchema, TSelect[number]> &
              (TLoad extends { user?: infer TUserConfig }
                ? { user: UserRelationship<TUserConfig> }
                : {}) &
              (TLoad extends { comment?: infer TCommentConfig }
                ? { comment: CommentRelationship<TCommentConfig> }
                : {})
          >
        : never
      : never;

// Comment-specific type inference system (for backward compatibility)
type CommentCalculatedFieldsResult<TCalc, TLoad> = PickFields<
  TCalc,
  ExtractCalculatedFields<TCalc, TLoad>
>;

// Main type inference for comment query results
type InferCommentQueryResult<TConfig> = TConfig extends {
  select: infer TSelect;
  load?: infer TLoad;
}
  ? TSelect extends readonly (keyof CommentSelectSchema)[]
    ? Array<
        PickFields<CommentSelectSchema, TSelect[number]> &
          (TLoad extends Record<string, any>
            ? CommentCalculatedFieldsResult<
                CommentCalculatedFieldsSchema,
                TLoad
              > &
                (TLoad extends { todo: infer TTodoConfig }
                  ? { todo: TodoRelationship<TTodoConfig> }
                  : {}) &
                (TLoad extends { user: infer TUserConfig }
                  ? { user: UserRelationship<TUserConfig> }
                  : {}) &
                (TLoad extends { likes: infer TLikesConfig }
                  ? { likes: CommentLikesArrayRelationship<TLikesConfig> }
                  : {})
            : {})
      >
    : never
  : never;

// Configuration type for reading comments
type ReadCommentsConfig = {
  select: readonly (keyof CommentSelectSchema)[];
  load?: {
    // Calculated fields
    [K in keyof CommentCalculatedFieldsSchema]?: boolean;
  } & {
    // Relationships
    todo?: {
      select: readonly (keyof TodoSelectSchema)[];
      load?: {
        [K in keyof TodoCalculatedFieldsSchema]?: boolean;
      };
    };
    user?: {
      select: readonly (keyof UserSelectSchema)[];
      load?: {
        todos?: {
          select: readonly (keyof TodoSelectSchema)[];
        };
        comment_likes?: {
          select: readonly (keyof CommentLikeSelectSchema)[];
        };
      };
    };
    likes?: Array<{
      select: readonly (keyof CommentLikeSelectSchema)[];
      load?: {
        user?: {
          select: readonly (keyof UserSelectSchema)[];
        };
      };
    }>;
  };
  filter?: any;
  sort?: any;
  limit?: number;
  offset?: number;
};

function buildReadCommentsPayload(config: any) {
  return {
    select: config.select,
    load: config.load,
    filter: config.filter,
    sort: config.sort,
    limit: config.limit,
    offset: config.offset,
  };
}

async function readComments<const T extends ReadCommentsConfig>(
  config: T,
): Promise<InferCommentQueryResult<T>> {
  const payload = buildReadCommentsPayload(config);
  const response = await fetch("/api/comments", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return response.json();
}

const todoListResult = await readTodos({
  select: ["id", "title", "completed", "status", "due_date"],
  load: {
    comment_count: true,
    is_overdue: true,
    user: {
      select: ["id", "email"],
      load: {
        comments: {
          select: ["id", "content", "author_name"],
          load: { user: { select: ["id", "email"] } },
        },
      },
    },
    comments: { select: ["id", "content", "author_name", "rating"] },
  },
});

// Expected type for todoListResult:
// Array<{
//   id: string,
//   title: string,
//   completed: boolean,
//   status: string,
//   due_date: string,
//   user: {
//     id: string,
//     email: string,
//     comments: Array<{id: string, content: string, author_name: string}>
//   },
//   comments: Array<{id: string, content: string, author_name: string, rating: number}>,
//   comment_count: number,
//   is_overdue: boolean
// }>
//

// Type debugging utilities
type DebugShow<T> = T extends never ? never : T;
type ResultType = DebugShow<typeof todoListResult>;

// Expected type structure
type ExpectedType = Array<{
  id: string;
  title: string;
  completed: boolean;
  status: "pending" | "ongoing" | "finished" | "cancelled";
  due_date: string | null;
  user: {
    id: string;
    email: string;
    comments: Array<{ id: string; content: string; author_name: string }>;
  };
  comments: Array<{
    id: string;
    content: string;
    author_name: string;
    rating: number | null;
  }>;
  comment_count: number;
  is_overdue: boolean;
}>;

// Verify that the inferred type is assignable to the expected type
const typeCheck: ExpectedType = todoListResult;

// Example 3: With simple relationships
const relationshipResult = await readTodos({
  select: ["id", "title"],
  load: {
    user: {
      select: ["id", "email"],
    },
    comments: {
      select: ["id", "content"],
    },
  },
});
// Type: Array<{ id: string; title: string; user: { id: string; email: string; }; comments: Array<{ id: string; content: string; }>; }>

// Example 4: Complex nested relationships
const complexResult = await readTodos({
  select: ["id", "title", "completed"],
  load: {
    comment_count: true,
    user: {
      select: ["id", "email"],
      load: {
        comments: {
          select: ["id", "content"],
        },
      },
    },
  },
});

// Example 4: Comments with todo relationship
const commentsWithTodo = await readComments({
  select: ["id", "content", "rating"],
  load: {
    todo: {
      select: ["id", "title", "status"],
      load: {
        comment_count: true,
        is_overdue: true,
      },
    },
  },
});
// Type: Array<{ id: string; content: string; rating: number | null; todo: { id: string; title: string; status: "pending" | "ongoing" | "finished" | "cancelled"; comment_count: number; is_overdue: boolean; }; }>

// Example 5: Complex comment query with multiple relationships
const complexComments = await readComments({
  select: ["id", "content", "author_name", "rating", "is_helpful"],
  load: {
    user: {
      select: ["id", "email"],
      load: {
        todos: {
          select: ["id", "title"],
          load: {
            user: {
              select: ["id", "email"],
            },
          },
        },
        comment_likes: {
          select: ["id"],
          load: {
            comment: {
              select: ["id", "content"],
            },
          },
        },
      },
    },
    todo: {
      select: ["id", "title", "status", "priority"],
      load: {
        comment_count: true,
      },
    },
    likes: [
      {
        select: ["id"],
        load: {
          user: {
            select: ["id", "email"],
          },
        },
      },
    ],
  },
});

export { readTodos, readComments };
