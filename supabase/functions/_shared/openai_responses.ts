export type HttpClient = (url: string, init: RequestInit) => Promise<Response>;

export const openAiResponsesEndpoint = "https://api.openai.com/v1/responses";
export const openAiDefaultModel = "gpt-5.6-sol";
export const defaultOpenAiTimeoutMs = 18_000;

export type OpenAiResponsesFailureReason =
  | "provider_http_error"
  | "provider_timeout"
  | "provider_incomplete"
  | "provider_refusal"
  | "provider_response_too_large"
  | "provider_response_invalid_json"
  | "provider_output_missing";

export class OpenAiResponsesFailure extends Error {
  readonly reason: OpenAiResponsesFailureReason;
  readonly httpStatus: number | undefined;

  constructor(reason: OpenAiResponsesFailureReason, httpStatus?: number) {
    super("OpenAI Responses request failed.");
    this.name = "OpenAiResponsesFailure";
    this.reason = reason;
    this.httpStatus = httpStatus;
  }
}

export async function sha256Hex(value: unknown): Promise<string> {
  const encoded = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function createOpenAiResponsesOutputText(dependencies: {
  http: HttpClient;
  apiKey: string;
  request: Record<string, unknown>;
  timeoutMs: number;
  maximumResponseBytes: number;
}): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), dependencies.timeoutMs);
  try {
    const response = await dependencies.http(openAiResponsesEndpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${dependencies.apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(dependencies.request),
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new OpenAiResponsesFailure("provider_http_error", response.status);
    }

    const rawJson = await readOpenAiResponseBody(
      response,
      controller,
      dependencies.maximumResponseBytes,
    );
    let responseJson: unknown;
    try {
      responseJson = JSON.parse(rawJson);
    } catch (_) {
      throw new OpenAiResponsesFailure("provider_response_invalid_json");
    }
    return completedAssistantOutputText(responseJson);
  } catch (error) {
    if (error instanceof OpenAiResponsesFailure) throw error;
    if (controller.signal.aborted) {
      throw new OpenAiResponsesFailure("provider_timeout");
    }
    throw new OpenAiResponsesFailure("provider_http_error");
  } finally {
    clearTimeout(timeout);
  }
}

export async function readBoundedUtf8Body(
  body: ReadableStream<Uint8Array> | null,
  contentLength: string | null,
  maximumBytes: number,
  createError: () => Error,
  signal?: AbortSignal,
): Promise<string> {
  if (
    body === null || !Number.isSafeInteger(maximumBytes) || maximumBytes < 1
  ) {
    throw createError();
  }
  if (declaredLengthExceedsLimit(contentLength, maximumBytes)) {
    await body.cancel().catch(() => undefined);
    throw createError();
  }

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const next = await readAbortableChunk(reader, signal);
      if (next.done) break;
      totalBytes += next.value.byteLength;
      if (totalBytes > maximumBytes) throw createError();
      chunks.push(next.value);
    }
  } catch (_) {
    await reader.cancel().catch(() => undefined);
    throw createError();
  } finally {
    reader.releaseLock();
  }

  return decodeUtf8(chunks, totalBytes, createError);
}

export function completedAssistantOutputText(value: unknown): string {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new OpenAiResponsesFailure("provider_output_missing");
  }
  const response = value as Record<string, unknown>;
  if (response.status === "incomplete") {
    throw new OpenAiResponsesFailure("provider_incomplete");
  }
  if (
    response.status !== "completed" || response.error !== null ||
    response.incomplete_details !== null || !Array.isArray(response.output)
  ) {
    throw new OpenAiResponsesFailure("provider_output_missing");
  }

  let outputText: string | null = null;
  let completedAssistantMessageFound = false;
  for (const item of response.output) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const outputItem = item as Record<string, unknown>;
    if (outputItem.type !== "message" || outputItem.role !== "assistant") {
      continue;
    }
    if (
      outputItem.status !== "completed" || !Array.isArray(outputItem.content)
    ) {
      throw new OpenAiResponsesFailure("provider_output_missing");
    }
    completedAssistantMessageFound = true;
    for (const part of outputItem.content) {
      if (part === null || typeof part !== "object" || Array.isArray(part)) {
        continue;
      }
      const contentPart = part as Record<string, unknown>;
      if (contentPart.type === "refusal") {
        throw new OpenAiResponsesFailure("provider_refusal");
      }
      if (contentPart.type !== "output_text") continue;
      if (typeof contentPart.text !== "string" || outputText !== null) {
        throw new OpenAiResponsesFailure("provider_output_missing");
      }
      outputText = contentPart.text;
    }
  }

  if (!completedAssistantMessageFound || outputText === null) {
    throw new OpenAiResponsesFailure("provider_output_missing");
  }
  return outputText;
}

async function readOpenAiResponseBody(
  response: Response,
  controller: AbortController,
  maximumBytes: number,
): Promise<string> {
  const body = response.body;
  if (body === null) {
    throw new OpenAiResponsesFailure("provider_output_missing");
  }
  if (
    declaredLengthExceedsLimit(
      response.headers.get("content-length"),
      maximumBytes,
    )
  ) {
    await body.cancel().catch(() => undefined);
    throw new OpenAiResponsesFailure("provider_response_too_large");
  }

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  let cancellationStarted = false;
  const cancelReader = async () => {
    if (cancellationStarted) return;
    cancellationStarted = true;
    await reader.cancel().catch(() => undefined);
  };
  try {
    while (true) {
      const next = await readAbortableChunk(reader, controller.signal);
      if (next.done) break;
      totalBytes += next.value.byteLength;
      if (totalBytes > maximumBytes) {
        throw new OpenAiResponsesFailure("provider_response_too_large");
      }
      chunks.push(next.value);
    }
  } catch (error) {
    await cancelReader();
    if (error instanceof OpenAiResponsesFailure) throw error;
    if (controller.signal.aborted) {
      throw new OpenAiResponsesFailure("provider_timeout");
    }
    throw new OpenAiResponsesFailure("provider_response_invalid_json");
  } finally {
    reader.releaseLock();
  }

  return decodeUtf8(
    chunks,
    totalBytes,
    () => new OpenAiResponsesFailure("provider_response_invalid_json"),
  );
}

function declaredLengthExceedsLimit(
  contentLength: string | null,
  maximumBytes: number,
): boolean {
  if (contentLength === null) return false;
  if (!/^[0-9]+$/.test(contentLength.trim())) return true;
  const declaredLength = Number(contentLength);
  return !Number.isSafeInteger(declaredLength) || declaredLength > maximumBytes;
}

async function readAbortableChunk(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  signal: AbortSignal | undefined,
): Promise<ReadableStreamReadResult<Uint8Array>> {
  if (signal === undefined) return reader.read();
  if (signal.aborted) throw new DOMException("Aborted", "AbortError");
  return await new Promise((resolve, reject) => {
    const onAbort = () => reject(new DOMException("Aborted", "AbortError"));
    signal.addEventListener("abort", onAbort, { once: true });
    void reader.read().then(resolve, reject).finally(() => {
      signal.removeEventListener("abort", onAbort);
    });
  });
}

function decodeUtf8(
  chunks: Uint8Array[],
  totalBytes: number,
  createError: () => Error,
): string {
  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (_) {
    throw createError();
  }
}
