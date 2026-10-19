import { Link } from "@tanstack/react-router"
import { Button } from "@/components/ui/button"

export default function AccessDenied() {
  return (
    <section className="flex flex-col items-start gap-4" role="alert">
      <h1 className="text-2xl font-bold tracking-tight">Access denied</h1>
      <p className="text-muted-foreground">
        Your account does not have permission to view this page.
      </p>
      <Button asChild variant="outline">
        <Link to="/">Go to dashboard</Link>
      </Button>
    </section>
  )
}
