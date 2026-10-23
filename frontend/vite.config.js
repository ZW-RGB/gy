import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 2005,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:2006',
        changeOrigin: true,
      }
    }
  }
})
