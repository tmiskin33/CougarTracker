// Parses the human-written dates a scraped page shows: "Sep 3",
// "9/3/2025", "Wed, Sep 3 at 11:59 PM", "Today". Port of
// LearningSuite/LearningSuiteDateParser.swift.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.CDT = Object.assign(root.CDT || {}, factory());
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const MONTHS = {
    jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
    jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12
  };

  // Learning Suite's own convention for "end of day", used when a row gives a
  // date but no time.
  const DEFAULT_HOUR = 23;
  const DEFAULT_MINUTE = 59;

  function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  function at(day, time) {
    const hour = time ? time.hour : DEFAULT_HOUR;
    const minute = time ? time.minute : DEFAULT_MINUTE;
    return new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute, 0, 0);
  }

  function makeDay(year, month, day) {
    const date = new Date(year, month - 1, day);
    // Reject rollovers like February 31st.
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null;
    return date;
  }

  // With no year on the page, pick the one that puts the date nearest to now:
  // a term spans a year boundary, so "Jan 8" seen in December means next year.
  function guessYear(month, day, now) {
    const year = now.getFullYear();
    let best = null;
    for (const candidate of [year - 1, year, year + 1]) {
      const made = makeDay(candidate, month, day);
      if (!made) continue;
      if (!best || Math.abs(made - now) < Math.abs(best - now)) best = made;
    }
    return best;
  }

  function findTime(text) {
    const match = /\b(\d{1,2}):(\d{2})\s*(am|pm)?/i.exec(text);
    if (!match) return null;
    let hour = parseInt(match[1], 10);
    const minute = parseInt(match[2], 10);
    if (!(hour >= 0 && hour <= 23) || !(minute >= 0 && minute <= 59)) return null;
    const meridiem = match[3] ? match[3].toLowerCase() : null;
    if (meridiem === 'pm' && hour < 12) hour += 12;
    if (meridiem === 'am' && hour === 12) hour = 0;
    return { hour: hour, minute: minute };
  }

  function findDate(text, now) {
    const reference = now || new Date();
    if (text == null) return null;

    const cleaned = String(text)
      .replace(/ /g, ' ')
      .replace(/ at /gi, ' ')
      .replace(/due:/gi, ' ')
      .replace(/due /gi, ' ')
      .trim();
    if (!cleaned) return null;

    const time = findTime(cleaned);
    const lowered = cleaned.toLowerCase();

    if (lowered.includes('today')) return at(startOfDay(reference), time);
    if (lowered.includes('tomorrow')) {
      const day = startOfDay(reference);
      day.setDate(day.getDate() + 1);
      return at(day, time);
    }
    if (lowered.includes('yesterday')) {
      const day = startOfDay(reference);
      day.setDate(day.getDate() - 1);
      return at(day, time);
    }

    // 9/3, 9/3/25, 9/3/2025, and the same with dashes.
    const numeric = /(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?/.exec(cleaned);
    if (numeric) {
      const month = parseInt(numeric[1], 10);
      const day = parseInt(numeric[2], 10);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        if (numeric[3]) {
          let year = parseInt(numeric[3], 10);
          if (year < 100) year += 2000;
          const made = makeDay(year, month, day);
          return made ? at(made, time) : null;
        }
        const guessed = guessYear(month, day, reference);
        return guessed ? at(guessed, time) : null;
      }
    }

    // "Sep 3", "September 3, 2025", "Wed, Sep 3".
    const named = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:\s*,?\s*(\d{4}))?/i.exec(cleaned);
    if (named) {
      const month = MONTHS[named[1].toLowerCase().slice(0, 3)];
      const day = parseInt(named[2], 10);
      if (month && day >= 1 && day <= 31) {
        if (named[3]) {
          const made = makeDay(parseInt(named[3], 10), month, day);
          return made ? at(made, time) : null;
        }
        const guessed = guessYear(month, day, reference);
        return guessed ? at(guessed, time) : null;
      }
    }

    return null;
  }

  return { findDate, findTime };
}));
