// Run with: node tests/test_temp_mail.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "TempMail.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(source, sandbox)
const TM = sandbox.module.exports

let failures = 0
function eq(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want)
  if (!ok) failures++
  console.log((ok ? "ok   " : "FAIL ") + name + (ok ? "" : "\n     got  " + JSON.stringify(got) + "\n     want " + JSON.stringify(want)))
}

eq("countdown 8:42", TM.formatCountdown(522000), "8:42")
eq("countdown 0", TM.formatCountdown(-5), "0:00")
eq("countdown 30:00", TM.formatCountdown(1800000), "30:00")

const now = new Date("2026-10-24T12:00:00Z")
eq("relative now", TM.relativeTime("2026-10-24T11:59:30Z", now), "now")
eq("relative 4m", TM.relativeTime("2026-10-24T11:56:00Z", now), "4m ago")
eq("relative 2h", TM.relativeTime("2026-10-24T10:00:00Z", now), "2h ago")
eq("relative bad", TM.relativeTime("nope", now), "")

eq("linkify escapes markup", TM.linkify("<script>x</script> & <b>"), "&lt;script&gt;x&lt;/script&gt; &amp; &lt;b&gt;")
eq("linkify url + trailing dot", TM.linkify("Go to https://a.com/x?y=1&z=2."),
  'Go to <a href="https://a.com/x?y=1&amp;z=2">https://a.com/x?y=1&amp;z=2</a>.')
eq("linkify ignores javascript:", TM.linkify("javascript:alert(1)"), "javascript:alert(1)")
eq("linkify newlines", TM.linkify("a\nb"), "a<br>b")
eq("linkify no attribute break", TM.linkify('https://a.com/"onclick=x').indexOf('"onclick'), -1)
eq("unescape", TM.unescapeHtml("https://a.com/x?y=1&amp;z=2"), "https://a.com/x?y=1&z=2")

eq("codes from verifications", TM.findCodes("", "", ["123456", "https://x.com/v"]), ["123456"])
eq("codes from objects", TM.findCodes("", "", [{ code: "AB12" }]), ["AB12"])
eq("codes from text", TM.findCodes("Welcome", "Your verification code is: 482913\nThanks", []), ["482913"])
eq("codes from subject", TM.findCodes("482913 is your login", "", []), ["482913"])
eq("no codes", TM.findCodes("Hello", "Order total 2026 items", []), [])

eq("sender name", TM.senderLabel("GitHub", "noreply@github.com"), "GitHub")
eq("sender address", TM.senderLabel("", "noreply@github.com"), "noreply@github.com")
eq("parseJson bad", TM.parseJson("{oops", []), [])
eq("parseJson ok", TM.parseJson('[{"id":"a"}]', []), [{ id: "a" }])

console.log(failures ? failures + " failed" : "all passed")
process.exit(failures ? 1 : 0)
