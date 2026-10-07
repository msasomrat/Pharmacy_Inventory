import { describe, expect, it, vi } from 'vitest'

import { handle, passwordProblem, type Deps } from './handler.ts'

const ORG = '11111111-1111-4111-8111-111111111111'

function request(
  body: unknown,
  init: { method?: string; auth?: string | null; origin?: string } = {},
) {
  const headers = new Headers({ 'content-type': 'application/json' })
  if (init.auth !== null) headers.set('authorization', init.auth ?? 'Bearer caller-jwt')
  if (init.origin) headers.set('origin', init.origin)
  return new Request('https://x.supabase.co/functions/v1/admin-users', {
    method: init.method ?? 'POST',
    headers,
    ...(init.method === 'OPTIONS' || init.method === 'GET' ? {} : { body: JSON.stringify(body) }),
  })
}

function deps(overrides: Partial<Deps> = {}): Deps {
  return {
    findInvitation: vi.fn().mockResolvedValue({ role: 'salesman' }),
    createUser: vi.fn().mockResolvedValue('created'),
    ...overrides,
  }
}

const valid = {
  organization_id: ORG,
  email: ' Sumi@Example.com ',
  password: 'Strong-Pass1',
  full_name: 'Sumi',
}

describe('passwordProblem', () => {
  it('enforces length and character classes', () => {
    expect(passwordProblem('Short1a')).toBe('password_length')
    expect(passwordProblem('alllowercase1')).toBe('password_weak')
    expect(passwordProblem('NoDigitsHere')).toBe('password_weak')
    expect(passwordProblem('Good-Pass123')).toBeNull()
  })
})

describe('admin-users handler', () => {
  it('creates the account only after the caller can see a pending invitation', async () => {
    const d = deps()
    const res = await handle(request(valid), d, ['*'])
    expect(res.status).toBe(201)
    expect(await res.json()).toEqual({ status: 'created' })
    expect(d.findInvitation).toHaveBeenCalledWith('caller-jwt', ORG, 'sumi@example.com')
    expect(d.createUser).toHaveBeenCalledWith('sumi@example.com', 'Strong-Pass1', 'Sumi')
  })

  it('refuses without an invitation visible to the caller (not owner, or not invited)', async () => {
    const d = deps({ findInvitation: vi.fn().mockResolvedValue(null) })
    const res = await handle(request(valid), d, ['*'])
    expect(res.status).toBe(403)
    expect(await res.json()).toEqual({ code: 'no_invitation' })
    expect(d.createUser).not.toHaveBeenCalled()
  })

  it('reports an existing account instead of failing', async () => {
    const res = await handle(
      request(valid),
      deps({ createUser: vi.fn().mockResolvedValue('exists') }),
      ['*'],
    )
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ status: 'exists' })
  })

  it('requires a bearer token', async () => {
    const d = deps()
    const res = await handle(request(valid, { auth: null }), d, ['*'])
    expect(res.status).toBe(401)
    expect(d.findInvitation).not.toHaveBeenCalled()
  })

  it('validates input before touching anything', async () => {
    const d = deps()
    const cases: [unknown, string][] = [
      [{ ...valid, organization_id: 'x' }, 'invalid_request'],
      [{ ...valid, email: 'nope' }, 'invalid_email'],
      [{ ...valid, password: 'weakpassword' }, 'password_weak'],
      ['not-an-object', 'invalid_request'],
    ]
    for (const [body, code] of cases) {
      const res = await handle(request(body), d, ['*'])
      expect(res.status).toBe(400)
      expect(await res.json()).toEqual({ code })
    }
    expect(d.findInvitation).not.toHaveBeenCalled()
  })

  it('answers CORS preflight and rejects other methods', async () => {
    const pre = await handle(
      request(null, { method: 'OPTIONS', origin: 'https://app.example' }),
      deps(),
      ['https://app.example'],
    )
    expect(pre.status).toBe(200)
    expect(pre.headers.get('access-control-allow-origin')).toBe('https://app.example')
    const get = await handle(request(null, { method: 'GET' }), deps(), ['*'])
    expect(get.status).toBe(405)
  })

  it('hides internal errors', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const res = await handle(
      request(valid),
      deps({ createUser: vi.fn().mockRejectedValue(new Error('db down: secret details')) }),
      ['*'],
    )
    expect(res.status).toBe(500)
    expect(await res.json()).toEqual({ code: 'unknown' })
    spy.mockRestore()
  })
})
