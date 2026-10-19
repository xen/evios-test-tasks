import { useQuery } from "@tanstack/react-query"
import { createFileRoute, ErrorComponent } from "@tanstack/react-router"
import { AxiosError } from "axios"
import { MetricsService } from "@/client"
import AccessDenied from "@/components/Common/AccessDenied"
import useAuth from "@/hooks/useAuth"
import { can } from "@/lib/permissions"

export const Route = createFileRoute("/_layout/metrics")({
  component: Metrics,
  errorComponent: ({ error }) =>
    error instanceof AxiosError && error.response?.status === 403 ? (
      <AccessDenied />
    ) : (
      <ErrorComponent error={error} />
    ),
  beforeLoad: ({ context }) => ({
    canReadMetrics: can(context.currentUser, "metrics:read"),
  }),
  head: () => ({ meta: [{ title: "Metrics - FastAPI Template" }] }),
})

function Metrics() {
  const { canReadMetrics } = Route.useRouteContext()
  const { user } = useAuth()
  const allowed = canReadMetrics && can(user, "metrics:read")
  const metrics = useQuery({
    queryKey: ["metrics"],
    queryFn: async () => (await MetricsService.readMetrics()).data,
    enabled: allowed,
  })
  if (
    !allowed ||
    (metrics.error instanceof AxiosError &&
      metrics.error.response?.status === 403)
  )
    return <AccessDenied />
  return (
    <section className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold tracking-tight">Metrics</h1>
      <p className="text-muted-foreground">
        Current application totals. Available to admins and managers.
      </p>
      {metrics.isPending ? (
        <p>Loading metrics…</p>
      ) : metrics.isError ? (
        <p role="alert">Unable to load metrics. Please try again.</p>
      ) : (
        <dl className="grid gap-4 sm:grid-cols-2">
          <div className="rounded-lg border p-6">
            <dt className="text-muted-foreground">Users</dt>
            <dd className="text-3xl font-bold">{metrics.data.users}</dd>
          </div>
          <div className="rounded-lg border p-6">
            <dt className="text-muted-foreground">Items</dt>
            <dd className="text-3xl font-bold">{metrics.data.items}</dd>
          </div>
        </dl>
      )}
    </section>
  )
}
