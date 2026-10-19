import { expect, test } from "@playwright/test"
import { firstSuperuser, firstSuperuserPassword } from "./config.ts"
import { randomEmail, randomPassword } from "./utils/random"
import { createUser } from "./utils/signup"
import { logInUser } from "./utils/user"

test("Admin page is accessible and shows correct title", async ({ page }) => {
  await page.goto("/admin")
  await expect(page.getByRole("heading", { name: "Users" })).toBeVisible()
  await expect(
    page.getByText("View user accounts and permissions"),
  ).toBeVisible()
})

test("Add User button is visible", async ({ page }) => {
  await page.goto("/admin")
  await expect(page.getByRole("button", { name: "Add User" })).toBeVisible()
})

test.describe("Admin user management", () => {
  test("Create a new user successfully", async ({ page }) => {
    await page.goto("/admin")

    const email = randomEmail()
    const password = randomPassword()
    const fullName = "Test User Admin"

    await page.getByRole("button", { name: "Add User" }).click()

    await page.getByPlaceholder("Email").fill(email)
    await page.getByPlaceholder("Full name").fill(fullName)
    await page.getByPlaceholder("Password").first().fill(password)
    await page.getByPlaceholder("Password").last().fill(password)

    await page.getByRole("button", { name: "Save" }).click()

    await expect(page.getByText("User created successfully")).toBeVisible()

    await expect(page.getByRole("dialog")).not.toBeVisible()

    const userRow = page.getByRole("row").filter({ hasText: email })
    await expect(userRow).toBeVisible()
  })

  test("Create an admin", async ({ page }) => {
    await page.goto("/admin")

    const email = randomEmail()
    const password = randomPassword()

    await page.getByRole("button", { name: "Add User" }).click()

    await page.getByPlaceholder("Email").fill(email)
    await page.getByPlaceholder("Password").first().fill(password)
    await page.getByPlaceholder("Password").last().fill(password)
    await page.getByLabel("Role", { exact: true }).selectOption("admin")
    await page.getByLabel("Is active?").check()

    await page.getByRole("button", { name: "Save" }).click()

    await expect(page.getByText("User created successfully")).toBeVisible()

    await expect(page.getByRole("dialog")).not.toBeVisible()

    const userRow = page.getByRole("row").filter({ hasText: email })
    await expect(userRow.getByText("admin", { exact: true })).toBeVisible()
  })

  test("Edit a user successfully", async ({ page }) => {
    await page.goto("/admin")

    const email = randomEmail()
    const password = randomPassword()
    const originalName = "Original Name"
    const updatedName = "Updated Name"

    await page.getByRole("button", { name: "Add User" }).click()
    await page.getByPlaceholder("Email").fill(email)
    await page.getByPlaceholder("Full name").fill(originalName)
    await page.getByPlaceholder("Password").first().fill(password)
    await page.getByPlaceholder("Password").last().fill(password)
    await page.getByRole("button", { name: "Save" }).click()

    await expect(page.getByText("User created successfully")).toBeVisible()
    await expect(page.getByRole("dialog")).not.toBeVisible()

    const userRow = page.getByRole("row").filter({ hasText: email })
    await userRow.getByRole("button").click()

    await page.getByRole("menuitem", { name: "Edit User" }).click()

    await page.getByPlaceholder("Full name").fill(updatedName)
    await page.getByRole("button", { name: "Save" }).click()

    await expect(page.getByText("User updated successfully")).toBeVisible()
    await expect(userRow.getByText(updatedName)).toBeVisible()
  })

  test("Delete a user successfully", async ({ page }) => {
    await page.goto("/admin")

    const email = randomEmail()
    const password = randomPassword()

    await page.getByRole("button", { name: "Add User" }).click()
    await page.getByPlaceholder("Email").fill(email)
    await page.getByPlaceholder("Password").first().fill(password)
    await page.getByPlaceholder("Password").last().fill(password)
    await page.getByRole("button", { name: "Save" }).click()

    await expect(page.getByText("User created successfully")).toBeVisible()

    await expect(page.getByRole("dialog")).not.toBeVisible()

    const userRow = page.getByRole("row").filter({ hasText: email })
    await userRow.getByRole("button").click()

    await page.getByRole("menuitem", { name: "Delete User" }).click()

    await page.getByRole("button", { name: "Delete" }).click()

    await expect(
      page.getByText("The user was deleted successfully"),
    ).toBeVisible()

    await expect(
      page.getByRole("row").filter({ hasText: email }),
    ).not.toBeVisible()
  })

  test("Cancel user creation", async ({ page }) => {
    await page.goto("/admin")

    await page.getByRole("button", { name: "Add User" }).click()
    await page.getByPlaceholder("Email").fill("test@example.com")

    await page.getByRole("button", { name: "Cancel" }).click()

    await expect(page.getByRole("dialog")).not.toBeVisible()
  })

  test("Email is required and must be valid", async ({ page }) => {
    await page.goto("/admin")

    await page.getByRole("button", { name: "Add User" }).click()

    await page.getByPlaceholder("Email").fill("invalid-email")
    await page.getByPlaceholder("Email").blur()

    await expect(page.getByText("Invalid email address")).toBeVisible()
  })

  test("Password must be at least 8 characters", async ({ page }) => {
    await page.goto("/admin")

    await page.getByRole("button", { name: "Add User" }).click()

    await page.getByPlaceholder("Email").fill(randomEmail())
    await page.getByPlaceholder("Password").first().fill("short")
    await page.getByPlaceholder("Password").last().fill("short")
    await page.getByRole("button", { name: "Save" }).click()

    await expect(
      page.getByText("Password must be at least 8 characters"),
    ).toBeVisible()
  })

  test("Passwords must match", async ({ page }) => {
    await page.goto("/admin")

    await page.getByRole("button", { name: "Add User" }).click()

    await page.getByPlaceholder("Email").fill(randomEmail())
    await page.getByPlaceholder("Password").first().fill(randomPassword())
    await page.getByPlaceholder("Password").last().fill("different12345")
    await page.getByPlaceholder("Password").last().blur()

    await expect(page.getByText("The passwords don't match")).toBeVisible()
  })
})

test.describe("Admin page access control", () => {
  test.use({ storageState: { cookies: [], origins: [] } })

  test("Member sees access denied on admin page", async ({ page }) => {
    const email = randomEmail()
    const password = randomPassword()

    await createUser({ email, password })
    await logInUser(page, email, password)

    await page.goto("/admin")

    await expect(page.getByRole("heading", { name: "Users" })).not.toBeVisible()
    await expect(
      page.getByRole("heading", { name: "Access denied" }),
    ).toBeVisible()
    await expect(page).toHaveURL(/\/admin/)
  })

  test("Admin can access admin page", async ({ page }) => {
    await logInUser(page, firstSuperuser, firstSuperuserPassword)

    await page.goto("/admin")

    await expect(page.getByRole("heading", { name: "Users" })).toBeVisible()
  })
})

test("Admin account deletion controls are hidden", async ({ page }) => {
  await page.goto("/settings")
  await expect(
    page.getByRole("heading", { name: "User Settings" }),
  ).toBeVisible()
  await expect(page.getByRole("tab", { name: "Danger zone" })).toHaveCount(0)
  await expect(
    page.getByRole("heading", { name: "Delete Account" }),
  ).toHaveCount(0)
})

test.describe("Role changes in the same browser session", () => {
  test.use({ storageState: { cookies: [], origins: [] } })

  test("Navigation refreshes capability checks and sidebar after demotion", async ({
    page,
    request,
  }) => {
    const api = process.env.VITE_API_URL
    if (!api) throw new Error("VITE_API_URL is required")
    const login = await request.post(`${api}/api/v1/login/access-token`, {
      form: { username: firstSuperuser, password: firstSuperuserPassword },
    })
    expect(login.ok()).toBeTruthy()
    const { access_token } = await login.json()
    const headers = { Authorization: `Bearer ${access_token}` }
    const email = randomEmail()
    const password = randomPassword()
    const created = await request.post(`${api}/api/v1/users/`, {
      headers,
      data: { email, password, role: "admin" },
    })
    expect(created.ok()).toBeTruthy()
    const user = await created.json()
    try {
      await logInUser(page, email, password)
      const manager = await request.patch(`${api}/api/v1/users/${user.id}`, {
        headers,
        data: { role: "manager" },
      })
      expect(manager.ok()).toBeTruthy()
      await page.getByRole("link", { name: "Users", exact: true }).click()
      await expect(
        page.getByRole("heading", { name: "Users", exact: true }),
      ).toBeVisible()
      await expect(page.getByRole("button", { name: "Add User" })).toHaveCount(
        0,
      )
      await expect(page.getByRole("table").getByRole("button")).toHaveCount(0)
      const member = await request.patch(`${api}/api/v1/users/${user.id}`, {
        headers,
        data: { role: "member" },
      })
      expect(member.ok()).toBeTruthy()
      await page.getByRole("link", { name: "Metrics", exact: true }).click()
      await expect(
        page.getByRole("heading", { name: "Access denied" }),
      ).toBeVisible()
      await expect(
        page.getByRole("link", { name: "Users", exact: true }),
      ).toHaveCount(0)
      await expect(
        page.getByRole("link", { name: "Metrics", exact: true }),
      ).toHaveCount(0)
      await expect(page.getByTestId("user-menu")).toContainText(email)
      await expect(page).toHaveURL(/\/metrics$/)
      await page.getByTestId("user-menu").click()
      await page.getByRole("menuitem", { name: "User Settings" }).click()
      await expect(page).toHaveURL(/\/settings$/)
      await expect(page.getByRole("tab", { name: "Danger zone" })).toBeVisible()
    } finally {
      const deleted = await request.delete(`${api}/api/v1/users/${user.id}`, {
        headers,
      })
      expect(deleted.ok()).toBeTruthy()
    }
  })
})
