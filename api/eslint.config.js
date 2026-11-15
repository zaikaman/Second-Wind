import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import eslintConfigPrettier from 'eslint-config-prettier';
import { sharedIgnores, sharedRules } from '../eslint.shared.mjs';

export default tseslint.config(
  { ignores: sharedIgnores },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.ts'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.node,
    },
    rules: {
      ...sharedRules,
    },
  },
  eslintConfigPrettier,
);
