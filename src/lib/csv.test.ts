import { describe, expect, it } from 'vitest'

import { csvCell, toCsv } from './csv'

describe('csv', () => {
  it('quotes separators and quotes', () => {
    expect(csvCell('Napa, 500 mg')).toBe('"Napa, 500 mg"')
    expect(csvCell('5" tube')).toBe('"5"" tube"')
    expect(csvCell(null)).toBe('')
    expect(csvCell(-12.5)).toBe('-12.5')
  })

  it('neutralises spreadsheet formulas in text cells', () => {
    expect(csvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`)
    expect(csvCell('+880171')).toBe("'+880171")
    expect(csvCell('@SUM(A1)')).toBe("'@SUM(A1)")
  })

  it('builds a BOM-prefixed CRLF document', () => {
    expect(toCsv(['a', 'b'], [[1, 'x']])).toBe('﻿a,b\r\n1,x\r\n')
  })
})
