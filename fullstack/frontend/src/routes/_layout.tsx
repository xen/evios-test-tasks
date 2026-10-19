import {
  createFileRoute,
  ErrorComponent,
  Outlet,
  redirect,
} from "@tanstack/react-router"

import { AxiosError } from "axios"
import AccessDenied from "@/components/Common/AccessDenied"
import { Footer } from "@/components/Common/Footer"
import AppSidebar from "@/components/Sidebar/AppSidebar"
import {
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar"
import { isLoggedIn } from "@/hooks/useAuth"
import { currentUserQueryOptions } from "@/lib/currentUser"
import { queryClient } from "@/lib/queryClient"

export const Route = createFileRoute("/_layout")({
  component: Layout,
  errorComponent: ({ error }) =>
    error instanceof AxiosError && error.response?.status === 403 ? (
      <AccessDenied />
    ) : (
      <ErrorComponent error={error} />
    ),
  beforeLoad: async () => {
    if (!isLoggedIn()) {
      throw redirect({
        to: "/login",
      })
    }
    const currentUser = await queryClient.fetchQuery({
      ...currentUserQueryOptions,
      staleTime: 0,
    })
    return { currentUser }
  },
})

function Layout() {
  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <header className="sticky top-0 z-10 flex h-16 shrink-0 items-center gap-2 border-b bg-background px-4">
          <SidebarTrigger className="-ml-1 text-muted-foreground" />
        </header>
        <main className="flex-1 p-6 md:p-8">
          <div className="mx-auto max-w-7xl">
            <Outlet />
          </div>
        </main>
        <Footer />
      </SidebarInset>
    </SidebarProvider>
  )
}
