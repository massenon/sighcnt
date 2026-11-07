/* Engendre prototype_html/mobile/ecrans/<id>.php depuis mobile/manifeste.js — dix lignes par page, comme la maquette. */
'use strict';
const fs = require('fs');
const path = require('path');
const M = require('../mobile/manifeste.js');
const dir = path.join(__dirname, '..', 'mobile', 'ecrans');
fs.mkdirSync(dir, { recursive: true });
fs.readdirSync(dir).filter((f) => f.endsWith('.php')).forEach((f) => fs.unlinkSync(path.join(dir, f)));
M.ECRANS.forEach((e) => {
  fs.writeFileSync(path.join(dir, e.id + '.php'), `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>${e.label} — SIGH-CNT mobile</title>
  <link rel="stylesheet" href="../mobile.css">
  <script src="../../assets/js/vendor/lucide.min.js"></script>
  <script src="../../assets/js/vendor/qr.js"></script>
  <script src="../manifeste.js"></script>
  <script src="../mobile.js"></script>
  <script src="../ecrans.js"></script>
</head>
<body><div id="app"></div><script>SIGHM.mount('${e.id}');</script></body>
</html>
`);
});
console.log(M.ECRANS.length + ' pages mobiles engendrées.');
