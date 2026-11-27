import { describe, it, expect } from 'vitest';
import { greet, add } from './utils';

describe('utils', () => {
  it('greet returns greeting', () => {
    expect(greet('World')).toBe('Hello, World!');
  });

  it('add returns sum', () => {
    expect(add(2, 3)).toBe(5);
    expect(add(-1, 1)).toBe(0);
  });
});