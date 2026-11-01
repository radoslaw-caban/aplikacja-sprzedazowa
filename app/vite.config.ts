import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  base: '/aplikacja-sprzedazowa/',
  plugins: [react()],
  // worker jako ES module — pozwala na dynamic import() dekodera WASM wewnątrz workera
  worker: { format: 'es' },
})
