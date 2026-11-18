// usage: node pdf.js in.html out.pdf
const { chromium } = require('playwright');
(async () => {
  const [inp, out] = process.argv.slice(2);
  const b = await chromium.launch(); const p = await b.newPage();
  await p.goto('file://' + require('path').resolve(inp), { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.pdf({ path: out, format: 'A4', printBackground: true, displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate: '<div style="width:100%;text-align:center;font-size:8px;color:#888;"><span class="pageNumber"></span> / <span class="totalPages"></span></div>',
    margin: { top: '13mm', bottom: '14mm', left: '13mm', right: '13mm' } });
  await b.close();
})();
