import { useSuspenseQuery } from "@tanstack/react-query"
import { createFileRoute, ErrorComponent } from "@tanstack/react-router"
import { AxiosError } from "axios"
import { Suspense } from "react"

import { type UserPublic, UsersService } from "@/client"
import AddUser from "@/components/Admin/AddUser"
import { columns, type UserTableData } from "@/components/Admin/columns"
import AccessDenied from "@/components/Common/AccessDenied"
import { DataTable } from "@/components/Common/DataTable"
import PendingUsers from "@/components/Pending/PendingUsers"
import useAuth from "@/hooks/useAuth"
import { can } from "@/lib/permissions"

function getUsersQueryOptions() {
  return {
    queryFn: async () =>
      (await UsersService.readUsers({ query: { skip: 0, limit: 100 } })).data,
    queryKey: ["users"],
  }
}

export const Route = createFileRoute("/_layout/admin")({
  component: Admin,
  errorComponent: ({ error }) =>
    error instanceof AxiosError && error.response?.status === 403 ? (
      <AccessDenied />
    ) : (
      <ErrorComponent error={error} />
    ),
  beforeLoad: ({ context }) => ({
    canReadUsers: can(context.currentUser, "users:read"),
  }),
  head: () => ({
    meta: [
      {
        title: "Admin - FastAPI Template",
      },
    ],
  }),
})

function UsersTableContent() {
  const { user: currentUser } = useAuth()
  const { data: users } = useSuspenseQuery(getUsersQueryOptions())

  const tableData: UserTableData[] = users.data.map((user: UserPublic) => ({
    ...user,
    isCurrentUser: currentUser?.id === user.id,
  }))

  return <DataTable columns={columns} data={tableData} />
}

function UsersTable() {
  return (
    <Suspense fallback={<PendingUsers />}>
      <UsersTableContent />
    </Suspense>
  )
}

function Admin() {
  const { canReadUsers } = Route.useRouteContext()
  const { user } = useAuth()
  if (!canReadUsers || !can(user, "users:read")) return <AccessDenied />
  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Users</h1>
          <p className="text-muted-foreground">
            View user accounts and permissions
          </p>
        </div>
        {can(user, "users:write") && <AddUser />}
      </div>
      <UsersTable />
    </div>
  )
}
