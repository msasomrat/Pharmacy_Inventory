// usage: node logo_render.cjs jobs.json   (jobs: [{html, png, w, h, transparent}])
const { chromium } = require('playwright');
const jobs = require(require('path').resolve(process.argv[2]));
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  for (const j of jobs) {
    await p.setViewportSize({ width: j.w, height: j.h });
    await p.goto('file://' + j.html, { waitUntil: 'load' });
    await p.evaluate(() => document.fonts.ready);
    await p.waitForTimeout(150);
    await p.screenshot({ path: j.png, omitBackground: !!j.transparent });
  }
  await b.close(); console.log('done', jobs.length);
})();
