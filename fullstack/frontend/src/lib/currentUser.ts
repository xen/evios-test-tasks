import { queryOptions } from "@tanstack/react-query"
import { UsersService } from "@/client"

export const currentUserQueryOptions = queryOptions({
  queryKey: ["currentUser"],
  queryFn: async () => (await UsersService.readUserMe()).data,
})
