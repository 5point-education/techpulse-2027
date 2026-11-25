import { describe, expect, it } from 'vitest';
import { emptyRegistration, makePublicId, validateRegistration } from './domain';

describe('registration validation', () => {
  it('keeps visitor registration independent of event selection', () => {
    const value = { ...emptyRegistration('visitor'), fullName:'Aritra Das', email:'aritra@example.com', phone:'9876543210', institutionName:'Example School', classYear:'Class X', consent:true };
    expect(validateRegistration(value,4)).toEqual([]);
  });
  it('requires a participant event', () => {
    const value = { ...emptyRegistration('participant'), fullName:'Aritra Das', email:'aritra@example.com', phone:'9876543210', institutionName:'Example School', classYear:'Class X', consent:true };
    expect(validateRegistration(value,4)).toContain('Select at least one competition.');
  });
  it('creates typed public ids', () => {
    expect(makePublicId('visitor')).toMatch(/^TP27-V-/);
    expect(makePublicId('participant')).toMatch(/^TP27-P-/);
  });
});
