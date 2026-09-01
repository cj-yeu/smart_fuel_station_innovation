import type { HttpClient } from "./openai_responses.ts";

export class AuthenticationUnavailable extends Error {
  constructor() {
    super("Supabase authentication is unavailable.");
    this.name = "AuthenticationUnavailable";
  }
}

export interface SupabaseAuthDependencies {
  http: HttpClient;
  supabaseUrl: string;
  supabaseAnonKey: string;
  timeoutMs?: number;
}

export async function verifySupabaseAccessToken(
  accessToken: string,
  dependencies: SupabaseAuthDependencies,
): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    dependencies.timeoutMs ?? 5_000,
  );
  try {
    const response = await dependencies.http(
      `${dependencies.supabaseUrl}/auth/v1/user`,
      {
        headers: {
          apikey: dependencies.supabaseAnonKey,
          authorization: `Bearer ${accessToken}`,
        },
        signal: controller.signal,
      },
    );
    if (response.status >= 500) throw new AuthenticationUnavailable();
    if (!response.ok) return false;
    const user = await response.json();
    if (
      user === null || typeof user !== "object" || Array.isArray(user) ||
      typeof (user as Record<string, unknown>).id !== "string" ||
      !(user as Record<string, unknown>).id
    ) {
      throw new AuthenticationUnavailable();
    }
    return true;
  } catch (error) {
    if (error instanceof AuthenticationUnavailable) throw error;
    throw new AuthenticationUnavailable();
  } finally {
    clearTimeout(timeout);
  }
}

export function parseBearerToken(value: string | null): string | null {
  if (value === null) return null;
  const match = /^Bearer\s+(.+)$/i.exec(value);
  return match?.[1]?.trim() || null;
}
