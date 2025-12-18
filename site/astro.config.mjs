import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://james-see.github.io',
  base: '/animus-visualizer',
  outDir: '../docs',
  build: {
    assets: '_astro'
  }
});
