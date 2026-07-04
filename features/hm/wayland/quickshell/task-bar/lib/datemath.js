// Pure date math shared by the calendar surfaces. Plain top-level JS so it is
// both a QML JS resource (import "../lib/datemath.js" as DateMath) and readable
// by the Deno test via indirect eval. Do NOT add `.pragma library` -- it is not
// valid standalone JS and would break the test's eval.

// Thursday-based ISO 8601 week number (1..53) for the week containing `date`.
// Computed in UTC so a DST midnight can never shift the day-count by one.
function isoWeek(date) {
    var d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    var dayNum = (d.getUTCDay() + 6) % 7;               // Mon=0 .. Sun=6
    d.setUTCDate(d.getUTCDate() - dayNum + 3);          // Thursday of this ISO week
    var firstThu = new Date(Date.UTC(d.getUTCFullYear(), 0, 4)); // Jan 4 is always in W1
    var firstDayNum = (firstThu.getUTCDay() + 6) % 7;
    firstThu.setUTCDate(firstThu.getUTCDate() - firstDayNum + 3); // Thursday of W1
    return 1 + Math.round((d - firstThu) / 604800000);  // 7 days in ms
}
