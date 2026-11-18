const { chromium } = require('playwright');
const jobs = require(process.argv[2]);
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  for (const j of jobs) {
    await p.setViewportSize({ width: j.w, height: j.h });
    await p.goto('file://' + j.html);
    await p.waitForSelector('body[data-ready="1"]', { timeout: 15000 });
    await p.screenshot({ path: j.png });
  }
  await b.close(); console.log('done', jobs.length);
})();
