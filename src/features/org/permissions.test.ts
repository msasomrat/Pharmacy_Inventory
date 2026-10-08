import { describe, expect, it } from 'vitest'

import { overridesFor, roleTemplate, withDependencies, type Permission } from './permissions'

describe('access editor rules', () => {
  it('sends only differences from the role template', () => {
    const effective = roleTemplate('salesman')
    effective.add('sales.void')
    effective.delete('customers.manage')
    expect(overridesFor('salesman', effective)).toEqual({
      'sales.void': true,
      'customers.manage': false,
    })
    expect(overridesFor('manager', roleTemplate('manager'))).toEqual({})
  })

  it('never sends owner-only permissions', () => {
    const effective = new Set<Permission>([...roleTemplate('manager'), 'users.manage'])
    expect(overridesFor('manager', effective)).toEqual({})
  })

  it('keeps purchases and cost visibility consistent', () => {
    const on = withDependencies(roleTemplate('salesman'), 'purchases.view', true)
    expect(on.has('reports.view_cost')).toBe(true)
    const off = withDependencies(roleTemplate('manager'), 'reports.view_cost', false)
    expect(off.has('purchases.view')).toBe(false)
  })
})
