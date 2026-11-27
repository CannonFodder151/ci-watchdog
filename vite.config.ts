import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    lib: {
      entry: 'src/utils.ts',
      name: 'utils',
      fileName: 'utils',
    },
  },
});