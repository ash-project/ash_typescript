// Resource schema constraint
type TypedSchema = {
  __type: "Resource" | "TypedStruct" | "TypedMap" | "Union";
  __primitiveFields: string;
};

type Relationship = {
  __type: "Relationship";
  __resource: TypedSchema;
  __array?: boolean;
};

type ComplexCalculation = {
  __type: "ComplexCalculation";
  __returnType: any;
};

// Now let's define the example schemas using the new approach
export type TodoResourceSchema = {
  __type: "Resource";
  __primitiveFields:
    | "id"
    | "title"
    | "description"
    | "dueDate"
    | "priority"
    | "status"
    | "completed"
    | "createdAt"
    | "userId";

  // Direct field access for type lookup
  id: string;
  title: string;
  description: string | null;
  dueDate: Date | null;
  priority: "low" | "medium" | "high" | "urgent" | null;
  status: "pending" | "ongoing" | "finished" | "cancelled" | null;
  completed: boolean | null;
  createdAt: string;
  userId: string;

  // Complex fields
  user?: UserRelationship;
  comments: TodoCommentArrayRelationship;
  metadata: TodoMetadataEmbedded;
  metadataHistory: TodoMetadataArrayEmbedded;
  content: ContentUnion;
  attachments: AttachmentUnion;
};

export type UserResourceSchema = {
  __type: "Resource";
  __primitiveFields: "id" | "name" | "email" | "createdAt";

  id: string;
  name: string;
  email: string;
  createdAt: string;

  todos: TodoArrayRelationship;
  comments: TodoCommentArrayRelationship;
};

export type TodoMetadataResourceSchema = {
  __type: "Resource";
  __primitiveFields: "id" | "category" | "tags" | "createdAt";

  id: string;
  category: string;
  tags: string[];
  createdAt: string;
};

// Relationship and embedded types
type UserRelationship = {
  __type: "Relationship";
  __resource: UserResourceSchema;
};

type TodoArrayRelationship = {
  __type: "Relationship";
  __array: true;
  __resource: TodoResourceSchema;
};

type TodoCommentArrayRelationship = {
  __type: "Relationship";
  __array: true;
  __resource: any; // Simplified for this example
};

type TodoMetadataEmbedded = {
  __type: "Relationship";
  __resource: TodoMetadataResourceSchema;
};

type TodoMetadataArrayEmbedded = {
  __type: "Relationship";
  __resource: TodoMetadataResourceSchema;
  __array: true;
};

type ContentUnion = {
  __type: "Union";
  __primitiveFields: "note" | "priorityValue";

  note?: string;
  priorityValue?: number;
  text?: {
    __type: "Resource";
    __primitiveFields: "content" | "wordCount" | "text" | "formatting";
    content: string;
    wordCount: number;
    text: string;
    formatting: "plain" | "markdown" | "html";
  };
}; // Simplified
type AttachmentUnion = Record<string, any>; // Simplified

export type GetTodoConfig = {
  fields: UnifiedFieldSelection<TodoResourceSchema>[];
  headers?: Record<string, string>;
  input?: any;
};

type InferGetTodoResult<Config extends GetTodoConfig> = InferResult<
  TodoResourceSchema,
  Config["fields"]
> | null;

export function buildGetTodoPayload(
  config: GetTodoConfig,
): Record<string, any> {
  const payload: Record<string, any> = {
    action: "get_todo",
    fields: config.fields,
  };

  if ("input" in config && config.input) {
    payload.input = config.input;
  } else {
    payload.input = {};
  }

  return payload;
}

export type GetTodoResult<Config extends GetTodoConfig> =
  | { success: true; data: InferGetTodoResult<Config> }
  | {
      success: false;
      errors: Array<{
        type: string;
        message: string;
        field_path?: string;
        details: Record<string, string>;
      }>;
    };

export async function getTodo<Config extends GetTodoConfig>(
  config: Config,
): Promise<
  | { success: true; data: InferGetTodoResult<Config> }
  | {
      success: false;
      errors: Array<{
        type: string;
        message: string;
        field_path?: string;
        details: Record<string, string>;
      }>;
    }
> {
  const payload = buildGetTodoPayload(config);

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...config.headers,
  };

  const response = await fetch("/rpc/run", {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    return {
      success: false,
      errors: [{ type: "network", message: response.statusText, details: {} }],
    };
  }

  const result = await response.json();
  return result as GetTodoResult<Config>;
}

type UnionToIntersection<U> = (U extends any ? (k: U) => void : never) extends (
  k: infer I,
) => void
  ? I
  : never;

type HasComplexFields<T extends TypedSchema> = keyof Omit<
  T,
  "__primitiveFields" | "__type" | T["__primitiveFields"]
> extends never
  ? false
  : true;

type ComplexFieldKeys<T extends TypedSchema> = keyof Omit<
  T,
  "__primitiveFields" | "__type" | T["__primitiveFields"]
>;

type LeafFieldSelection<T extends TypedSchema> = T["__primitiveFields"];

type ComplexFieldSelection<T extends TypedSchema> = {
  [K in ComplexFieldKeys<T>]?: NonNullable<T[K]> extends {
    __type: "Relationship";
    __resource: infer R extends TypedSchema;
  }
    ? UnifiedFieldSelection<R>[]
    : NonNullable<T[K]> extends TypedSchema
      ? UnifiedFieldSelection<NonNullable<T[K]>>[]
      : never;
};

// Main type: Use explicit base case detection to prevent infinite recursion
type UnifiedFieldSelection<T extends TypedSchema> =
  HasComplexFields<T> extends false
    ? LeafFieldSelection<T> // Base case: only primitives, no recursion
    : LeafFieldSelection<T> | ComplexFieldSelection<T>; // Recursive case

type InferFieldValue<
  T extends TypedSchema,
  Field,
> = Field extends T["__primitiveFields"]
  ? Field extends keyof T
    ? { [K in Field]: T[Field] }
    : never
  : Field extends Record<string, any>
    ? {
        [K in keyof Field]: K extends keyof T
          ? NonNullable<T[K]> extends {
              __type: "Relationship";
              __resource: infer R extends TypedSchema;
            }
            ? T[K] extends { __array: true }
              ? Array<InferResult<R, Field[K]>>
              : undefined extends T[K]
                ? InferResult<R, Field[K]> | undefined
                : InferResult<R, Field[K]>
            : NonNullable<T[K]> extends TypedSchema
              ? undefined extends T[K]
                ? InferResult<NonNullable<T[K]>, Field[K]> | undefined
                : InferResult<NonNullable<T[K]>, Field[K]>
              : never
          : never;
      }
    : never;

type InferResult<
  T extends TypedSchema,
  SelectedFields extends UnifiedFieldSelection<T>[],
> = UnionToIntersection<
  {
    [K in keyof SelectedFields]: InferFieldValue<T, SelectedFields[K]>;
  }[number]
>;

async function testUnionFieldSelection() {
  const result = await getTodo({
    fields: [
      "id",
      "title",
      "description",
      {
        user: ["id", "email", "name", { todos: ["id"] }],
        metadata: ["tags", "createdAt"],
        content: [
          "note",
          "priorityValue",
          { text: ["content", "text", "wordCount"] },
        ],
      },
    ],
  });

  if (result.success && result.data) {
    const data = result.data;
    const id: string = data.id;
    const title: string = data.title;

    const user: { id: string } | undefined = data.user;
    const content: string | undefined = data.content.note;
    const text: { content: string } | undefined = data.content?.text;
    const description: string | null = data.description;
    const tags: string[] = data.metadata.tags;
  }
}
