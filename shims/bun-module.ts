/* Shim for the "bun" module */

import { pathToFileURL as nodePathToFileURL, fileURLToPath as nodeFileURLToPath } from "url"

export const pathToFileURL = nodePathToFileURL
export const fileURLToPath = nodeFileURLToPath

export interface SystemError extends Error {
  code?: string
  syscall?: string
}
