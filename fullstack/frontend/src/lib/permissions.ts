import type { UserPublic } from "@/client"

export function can(
  user: UserPublic | null | undefined,
  permission: UserPublic["permissions"][number],
) {
  return user?.permissions.includes(permission) === true
}
