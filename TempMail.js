.pragma library

// Pure helpers for the Temp Mail widget: no QML dependencies, so
// tests/test_temp_mail.js can run them under node.

function pad2(n) { return (n < 10 ? "0" : "") + n }

// 522000 -> "8:42"
function formatCountdown(ms) {
  var s = Math.max(0, Math.ceil(ms / 1000))
  return Math.floor(s / 60) + ":" + pad2(s % 60)
}

// ISO date -> "now", "4m ago", "2h ago", "3d ago"
function relativeTime(iso, now) {
  var t = new Date(iso).getTime()
  if (isNaN(t)) return ""
  var s = Math.max(0, Math.floor((now.getTime() - t) / 1000))
  if (s < 60) return "now"
  if (s < 3600) return Math.floor(s / 60) + "m ago"
  if (s < 86400) return Math.floor(s / 3600) + "h ago"
  return Math.floor(s / 86400) + "d ago"
}

function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}

// Plain text -> StyledText: escaped, with http(s) URLs as links and
// newlines as <br>. Nothing from the email is ever treated as markup.
function linkify(text) {
  var escaped = escapeHtml(text)
  var linked = escaped.replace(/https?:\/\/[^\s<>"']+/g, function(url) {
    var trimmed = url.replace(/[.,;:!?)\]]+$/, "")
    var rest = url.substring(trimmed.length)
    return '<a href="' + trimmed + '">' + trimmed + '</a>' + rest
  })
  return linked.replace(/\r?\n/g, "<br>")
}

// Decode the entities escapeHtml added, for a link handed to the browser.
function unescapeHtml(text) {
  return String(text || "").replace(/&#39;/g, "'").replace(/&quot;/g, '"')
    .replace(/&gt;/g, ">").replace(/&lt;/g, "<").replace(/&amp;/g, "&")
}

// Verification codes: mail.tm's own `verifications` first (strings, or
// objects with a code/value field; links are skipped), then 4-8 digit
// numbers near a code-like word in the subject or text.
function findCodes(subject, text, verifications) {
  var out = []
  function add(c) {
    c = String(c || "").trim()
    if (c && !/^https?:/i.test(c) && out.indexOf(c) < 0 && c.length <= 12) out.push(c)
  }
  var list = verifications || []
  for (var i = 0; i < list.length; i++) {
    var v = list[i]
    add(typeof v === "object" && v ? (v.code || v.value || "") : v)
  }
  if (out.length) return out.slice(0, 3)
  var hay = String(subject || "") + "\n" + String(text || "")
  var re = /(?:code|pin|otp|verif\w*|confirm\w*|password|كود|رمز)[^\d\n]{0,40}(\d{4,8})\b/gi
  var m
  while ((m = re.exec(hay)) !== null && out.length < 3) add(m[1])
  if (!out.length) {
    var s = /\b(\d{4,8})\b/.exec(String(subject || ""))
    if (s) add(s[1])
  }
  return out
}

function senderLabel(name, address) {
  name = String(name || "").trim()
  return name !== "" ? name : String(address || "unknown")
}

function parseJson(text, fallback) {
  try {
    var data = JSON.parse(String(text || ""))
    return data === null || data === undefined ? fallback : data
  } catch (e) {
    return fallback
  }
}

if (typeof module !== "undefined") module.exports = {
  formatCountdown: formatCountdown, relativeTime: relativeTime, escapeHtml: escapeHtml,
  linkify: linkify, unescapeHtml: unescapeHtml, findCodes: findCodes,
  senderLabel: senderLabel, parseJson: parseJson
}
