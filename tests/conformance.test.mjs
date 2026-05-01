import { describe } from "vitest"
import { runConformanceTests } from "@durable-streams/server-conformance-tests"

const baseUrl = process.env.DS_URL ?? "http://localhost:14437"

describe("durable-streams-caddy", () => {
  runConformanceTests({ baseUrl })
})
