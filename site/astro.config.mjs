import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://james-see.github.io',
  base: '/animus-visualizer/',
  outDir: '../docs',
  build: {
    assets: '_astro',
    inlineStylesheets: 'never'
  },
  vite: {
    build: {
      assetsInlineLimit: 0,
      rollupOptions: {
        output: {
          entryFileNames: '_astro/[name].[hash].js',
          chunkFileNames: '_astro/[name].[hash].js',
          assetFileNames: '_astro/[name].[hash][extname]'
        }
      }
    }
  }
});
