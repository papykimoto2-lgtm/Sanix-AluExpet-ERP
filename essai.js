/* Sanix AluExpert ERP — essai gratuit de 30 jours.
   - Un essai est un espace LOCAL à l'appareil : jamais connecté au cloud SANIX (le projet Supabase de production est neutralisé).
   - Bandeau « X jours restants » tant que l'essai court.
   - À l'expiration : écran de verrouillage (export des données + contact), impossible à fermer.
   - Horloge : la dernière date vue est mémorisée, reculer l'heure de l'appareil ne prolonge pas l'essai.
   Ce fichier est chargé juste après la configuration SANIX_CFG, avant le code de l'application. */
(function () {
  'use strict';

  var KEY = 'alu_trial';
  var DAY_MS = 86400000;
  var trial = null;
  try { trial = JSON.parse(localStorage.getItem(KEY)); } catch (x) {}
  if (!trial || !trial.end) return;

  /* Essai = local : le cloud de production ne doit jamais être joint, quelle que soit la configuration enregistrée */
  try {
    var cfg = window.SANIX_CFG || (window.SANIX_CFG = {});
    var FIXED = { SUPABASE_URL: 'https://VOTRE-PROJET.supabase.co', SUPABASE_ANON_KEY: 'VOTRE_ANON_KEY' };
    Object.keys(FIXED).forEach(function (k) {
      Object.defineProperty(cfg, k, { get: function () { return FIXED[k]; }, set: function () {}, configurable: false, enumerable: true });
    });
    localStorage.removeItem('alubom_cloud_config_override');
  } catch (x) {}

  function save() { try { localStorage.setItem(KEY, JSON.stringify(trial)); } catch (x) {} }

  function now() {
    var n = Math.max(Date.now(), trial.last || 0);
    if (n !== trial.last) { trial.last = n; save(); }
    return n;
  }

  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }

  function style() {
    if (document.getElementById('trial-css')) return;
    var s = document.createElement('style'); s.id = 'trial-css';
    s.textContent =
      '#trial-chip{position:fixed;left:14px;bottom:14px;z-index:9000;background:#fff7ed;color:#c2410c;border:1px solid #fb923c;border-radius:999px;padding:7px 14px;font:600 13px/1.3 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;box-shadow:0 4px 14px rgba(0,0,0,.18)}' +
      '#trial-chip.warn{background:#fef2f2;color:#b91c1c;border-color:#f87171}' +
      '#trial-chip a{color:inherit;margin-left:8px;text-decoration:underline}' +
      '@media (max-width:599px){#trial-chip{bottom:70px;left:8px;right:8px;text-align:center;border-radius:12px}}' +
      '#trial-lock{position:fixed;inset:0;z-index:2147483647;background:#1a1d21;color:#f5f6f7;display:flex;align-items:center;justify-content:center;padding:20px;font:15px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}' +
      '#trial-lock .box{max-width:460px;width:100%;background:#242830;border:1px solid rgba(255,255,255,.14);border-radius:14px;padding:24px;text-align:center}' +
      '#trial-lock h1{font-size:21px;font-weight:800;margin-bottom:8px}#trial-lock p{color:#b6bcc6;font-size:14px;margin:8px 0}' +
      '#trial-lock button,#trial-lock a.btn{display:block;width:100%;min-height:50px;line-height:50px;border:0;border-radius:10px;font:600 15px system-ui,sans-serif;cursor:pointer;color:#fff;text-decoration:none;margin-top:12px;background:#ff5a1f}' +
      '#trial-lock button.sec,#trial-lock a.sec{background:#2f343d;border:1px solid rgba(255,255,255,.14)}' +
      '#trial-lock .who{margin-top:16px;font-size:13px;color:#f5f6f7}';
    document.head.appendChild(s);
  }

  /* ── Sauvegarde des données (fichier JSON) : réglages du navigateur + base IndexedDB de l'application ── */
  function dumpIndexedDb() {
    return new Promise(function (resolve) {
      var out = {};
      try {
        var req = indexedDB.open('alubom_db');
        req.onerror = function () { resolve(out); };
        req.onsuccess = function () {
          var db = req.result, names = Array.prototype.slice.call(db.objectStoreNames);
          if (!names.length) { db.close(); resolve(out); return; }
          var left = names.length;
          names.forEach(function (n) {
            var r = db.transaction(n, 'readonly').objectStore(n).getAll();
            r.onsuccess = function () { out[n] = r.result; if (--left === 0) { db.close(); resolve(out); } };
            r.onerror = function () { out[n] = []; if (--left === 0) { db.close(); resolve(out); } };
          });
        };
      } catch (x) { resolve(out); }
    });
  }

  function exportData() {
    var settings = {};
    Object.keys(localStorage).forEach(function (k) {
      if (/^(alubom_|sanix_|alu_)/.test(k) && k !== 'alubom_session_local' && k !== 'alubom_local_users') settings[k] = localStorage.getItem(k);
    });
    dumpIndexedDb().then(function (tables) {
      var blob = new Blob([JSON.stringify({ app: 'Sanix AluExpert ERP', societe: trial.societe, exporte_le: new Date().toISOString(), reglages: settings, tables: tables })], { type: 'application/json' });
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'aluexpert-sauvegarde-' + new Date().toISOString().slice(0, 10) + '.json';
      document.body.appendChild(a); a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    });
  }

  function lock() {
    style();
    var chip = document.getElementById('trial-chip'); if (chip) chip.remove();
    if (document.getElementById('trial-lock')) return;
    var d = document.createElement('div');
    d.id = 'trial-lock'; d.setAttribute('role', 'alertdialog'); d.setAttribute('aria-modal', 'true');
    d.innerHTML =
      '<div class="box"><div style="font-size:40px">⏳</div>' +
      '<h1>Votre essai gratuit est terminé</h1>' +
      '<p>Merci d\'avoir testé Sanix AluExpert ERP' + (trial.societe ? ' pour <b>' + esc(trial.societe) + '</b>' : '') + '.<br>Vos données sont conservées sur cet appareil : rien n\'est perdu.</p>' +
      '<p>Pour continuer à utiliser le logiciel, contactez-nous.</p>' +
      '<a class="btn" href="https://wa.me/2250779181075?text=' + encodeURIComponent('Bonjour, mon essai AluExpert est terminé, je souhaite continuer.') + '" target="_blank" rel="noopener">💬 Nous écrire sur WhatsApp</a>' +
      '<a class="btn sec" href="tel:+2250779181075">📞 +225 07 79 18 10 75</a>' +
      '<button class="sec" type="button" id="trial-export">💾 Télécharger une sauvegarde de mes données</button>' +
      '<div class="who">SANIX AFRICA · Division Technologies<br>sanixafrica699@gmail.com</div></div>';
    document.body.appendChild(d);
    document.getElementById('trial-export').addEventListener('click', exportData);
  }

  function banner(left) {
    style();
    var c = document.getElementById('trial-chip');
    if (!c) { c = document.createElement('div'); c.id = 'trial-chip'; document.body.appendChild(c); }
    c.className = left <= 5 ? 'warn' : '';
    c.innerHTML = '⏳ <b>Essai gratuit</b> · ' + left + ' jour' + (left > 1 ? 's' : '') + ' restant' + (left > 1 ? 's' : '') +
      ' <a href="https://wa.me/2250779181075" target="_blank" rel="noopener">Continuer</a>';
  }

  function check() {
    if (!document.body) return;
    var n = now();
    if (n >= trial.end) { lock(); return; }
    banner(Math.max(1, Math.ceil((trial.end - n) / DAY_MS)));
  }

  /* L'essai ne préremplit pas les identifiants de démonstration : le formulaire reprend l'adresse du compte d'essai */
  function loginForm() {
    var e = document.getElementById('loginEmail'), p = document.getElementById('loginPassword');
    if (e && trial.email) e.value = trial.email;
    if (p) p.value = '';
  }

  function init() {
    loginForm();
    check();
    setInterval(check, 60000);
    document.addEventListener('visibilitychange', function () { if (!document.hidden) check(); });
    /* L'écran de verrouillage ne peut pas être retiré depuis la console / les outils du navigateur */
    new MutationObserver(function () {
      if (now() >= trial.end && !document.getElementById('trial-lock')) lock();
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
