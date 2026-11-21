// Shared by the public form and the staff page, so a phone number is stored and
// searched in ONE format everywhere: +2376XXXXXXXX
//
// Accepts 6XXXXXXXX, 2376XXXXXXXX and +2376XXXXXXXX, typed with spaces, dashes,
// dots or parentheses. Returns the canonical number, or null when it is not a
// Cameroon mobile number.
function normalizePhone(value) {
  var cleaned = String(value == null ? '' : value).replace(/[\s\-.()]/g, '');
  var match = /^(?:\+?237)?(6\d{8})$/.exec(cleaned);
  return match ? '+237' + match[1] : null;
}
