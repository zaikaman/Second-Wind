// Shared ESLint settings for `web/` and `api/`.
// Deliberately dependency-free: each app imports this file and adds its own
// plugins, so the two apps cannot drift apart on the basics.

/** Build output and generated files are never linted. */
export const sharedIgnores = [
  '**/dist/**',
  '**/node_modules/**',
  '**/coverage/**',
  '**/*.min.js',
];

/** Rules both apps apply. */
export const sharedRules = {
  eqeqeq: ['error', 'smart'],
  'no-var': 'error',
  'prefer-const': 'error',
  'no-console': ['warn', { allow: ['warn', 'error'] }],
  '@typescript-eslint/no-unused-vars': [
    'error',
    { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
  ],
};
